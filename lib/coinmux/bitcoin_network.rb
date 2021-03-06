class Coinmux::BitcoinNetwork
  include Singleton, Coinmux::BitcoinUtil, Coinmux::Facades

  import 'com.google.bitcoin.core.Transaction'
  import 'java.math.BigInteger'
  import 'java.security.SignatureException'
  import 'com.google.bitcoin.core.Address'
  import 'com.google.bitcoin.core.ECKey'
  import 'com.google.bitcoin.core.NetworkParameters'
  import 'com.google.bitcoin.core.PeerGroup'
  import 'com.google.bitcoin.core.ScriptException'
  import 'com.google.bitcoin.core.Utils'
  import 'com.google.bitcoin.core.VerificationException'
  import 'com.google.bitcoin.crypto.TransactionSignature'
  import 'com.google.bitcoin.script.Script'
  import 'com.google.bitcoin.script.ScriptBuilder'
  import 'com.google.bitcoin.net.discovery.DnsDiscovery'
  import 'org.spongycastle.util.encoders.Hex'

  # @address [String] Input address.
  # @callback [Proc, nil] Invoked with a Coinmux::Event with data or error set.
  # @return [Hash] Hash with keys being `{id: 'transaction hash identifier', index: 'unspent transaction output index'}` and the value being the unspent amount. Only returns when no callback.
  # @raise [Coinmux::Error] Only raises when no callback
  def unspent_inputs_for_address(address, &callback)
    exec(callback) do
      data = webbtc_get_json("/address/#{address}.json")

      build_unspent_inputs_from_data(data, address)
    end
  end

  # @unspent_inputs [Array] Array of hashes with keys being `:id` (transaction hash identifier), `:index` (the index of the unspent output).
  # @outputs [Array] Array of hashes with keys being `:address` and `:amount`.
  # @callback [Proc, nil] Invoked with a Coinmux::Event with data or error set.
  # @return [Object] A transaction with inputs linked to the transactions from `unspent_transaction_input_hashes` in the order specified. Only returns when no callback.
  # @raise [Coinmux::Error] Only raises when no callback
  def build_unsigned_transaction(unspent_inputs, outputs, &callback)
    exec(callback) do
      Transaction.new(network_params).tap do |transaction|
        unspent_inputs.each do |tx_hash|
          input_tx = fetch_transaction(tx_hash[:id])
          raise Coinmux::Error, "Output index does not exist" if tx_hash[:index].to_s.to_i < 0 || tx_hash[:index].to_s.to_i >= input_tx.getOutputs().size()
          tx_output = input_tx.getOutput(tx_hash[:index])
          transaction.addInput(tx_output)
        end

        outputs.each do |hash|
          transaction.addOutput(BigInteger.new(hash[:amount].to_s), Address.new(network_params, hash[:address]))
        end
      end
    end
  end

  # @transaction [Object] Transaction returned from `#build_unsigned_transaction`.
  # @input_index [Fixnum] The index of the input.
  # @private_key_hex [String] The private key used to sign the input at this index.
  # @return [String] The script_sig used for signing this (and only this) transaction.
  # @raise [Coinmux::Error]
  def build_transaction_input_script_sig(transaction, input_index, private_key_hex)
    tx_input = get_unspent_tx_input(transaction, input_index)
    key = build_ec_key(private_key_hex)
    connected_pub_key_script = tx_input.getOutpoint().getConnectedPubKeyScript()
    script_public_key = tx_input.getOutpoint().getConnectedOutput().getScriptPubKey().to_s

    signature = transaction.calculateSignature(input_index, key, nil, connected_pub_key_script, Transaction::SigHash::ALL, false)
    script_sig = ScriptBuilder.createInputScript(signature, key)

    script_sig.getProgram().collect(&:to_i).pack('c*')
  end

  # @transaction [Object] Transaction returned from `#build_unsigned_transaction`
  # @input_index [Fixnum] The index of the input.
  # @return [true, false]
  def transaction_input_unspent?(transaction, input_index)
    begin
      get_unspent_tx_input(transaction, input_index)
      true
    rescue Coinmux::Error
      false
    end
  end

  # @transaction [Object] Transaction returned from `#build_unsigned_transaction`
  # @input_index [Fixnum] The index of the input.
  # @script_sig [String] The script_sig used for signing this index.
  # @return [true, false]
  def script_sig_valid?(transaction, input_index, script_sig)
    begin
      set_transaction_script_sig(clone_transaction(transaction), input_index, script_sig)
      true
    rescue Coinmux::Error
      debug "Script Sig is not valid: #{$!}"
      false
    end
  end

  # @transaction [Object] Transaction returned from `#build_unsigned_transaction`
  # @input_index [Fixnum] The index of the input.
  # @script_sig [String] The script_sig used for signing this index.
  # @raise [Coinmux::Error]
  def sign_transaction_input(transaction, input_index, script_sig)
    set_transaction_script_sig(transaction, input_index, script_sig)
    nil
  end

  # @transaction [Object] Transaction returned from `#build_unsigned_transaction` and all inputs signed with `#sign_transaction_input`
  # @callback [Proc, nil] Invoked with a Coinmux::Event with data or error set.
  # @return [String] The transaction hash. Only returns when no callback.
  # @raise [Coinmux::Error] Only raises when no callback
  def post_transaction(transaction, &callback)
    exec(callback) do
      result = webbtc_post_bin("/relay_tx", tx: transaction.bitcoinSerialize().collect(&:to_i).pack('c*').unpack('H*').first)

      result['hash']
    end
  end

  private

  def clone_transaction(source)
    inputs = source.getInputs().collect do |input|
      out = input.getOutpoint()
      { id: out.getHash().toString(), index: out.getIndex() }
    end
    outputs = source.getOutputs().collect do |output|
      { address: output.getScriptPubKey().getToAddress(network_params).toString(), amount: output.getValue() }
    end

    build_unsigned_transaction(inputs, outputs)
  end

  def set_transaction_script_sig(transaction, input_index, script_sig)
    begin
      script_sig = Script.new(script_sig.unpack('c*').to_java(:byte))

      tx_input = get_unspent_tx_input(transaction, input_index)
      tx_input.setScriptSig(script_sig)
      tx_input.verify()

      tx_input
    rescue ScriptException => e
      raise Coinmux::Error, "Unable to verify signature: #{e}"
    rescue VerificationException => e
      raise Coinmux::Error, "Unable to verify signature: #{e}"
    end
  end

  def fetch_transaction(transaction_hash)
    bytes = webbtc_get_bin("/tx/#{transaction_hash}.bin").unpack('c*').to_java(:byte)
    Transaction.new(network_params, bytes)
  end

  # @transaction [Object] Transaction returned from `#build_unsigned_transaction`
  # @input_index [Fixnum] The index of the input.
  # @return [TransactionInput] A verified unspent input.
  # @raise [Coinmux::Error]
  def get_unspent_tx_input(transaction, input_index)
    input_index = input_index.to_s.to_i
    raise Coinmux::Error, "Invalid input index" if input_index < 0 || input_index >= transaction.getInputs().size()
    tx_input = transaction.getInput(input_index)
    raise Coinmux::Error, "No connected output: #{tx_input}" if tx_input.getOutpoint().getConnectedOutput().nil?
    raise Coinmux::Error, "Signing already signed transaction: #{tx_input}" if tx_input.getScriptBytes().length != 0
    begin
      tx_input.getScriptSig().correctlySpends(transaction, input_index, tx_input.getOutpoint().getConnectedOutput().getScriptPubKey(), true)
      raise Coinmux::Error, "Input already spent: #{tx_input}"
    rescue ScriptException
      # input not spent... what we want
    end

    tx_input
  end

  def build_unspent_inputs_from_data(data, address)
    all_inputs = data['transactions'].values.inject({}) do |acc, txn|
      txn['out'].each_with_index do |out, index|
        if out['address'] == address
          acc[{id: txn['hash'], index: index}] = (out['value'].to_f * SATOSHIS_PER_BITCOIN).to_i
        end
      end

      acc
    end

    unspent_inputs = data['transactions'].values.inject(all_inputs.dup) do |acc, txn|
      txn['in'].each do |in_|
        next unless prev_out = in_['prev_out']
        acc.delete({id: prev_out['hash'], index: prev_out['n']})
      end

      acc
    end

    unspent_inputs
  end

  def build_ec_key(private_key_hex)
    ECKey.new(BigInteger.new(private_key_hex, 16))
  end

  def exec(callback, &block)
    exec = lambda do
      begin
        result = yield

        Coinmux::Event.new(data: result)
      rescue Coinmux::Error => e
        Coinmux::Event.new(error: e.message)
      rescue StandardError => e
        puts e, e.backtrace
        Coinmux::Event.new(error: "Unknown error: #{e.message}")
      end
    end

    if callback.nil?
      event = exec.call
      raise Coinmux::Error, event.error if event.error

      event.data
    else
      Thread.new do
        callback.call(exec.call)
      end

      nil
    end
  end

  def webbtc_post_bin(path, data)
    result = http_facade.post(config_facade.webbtc_host, path, data)

    hash = JSON.parse(result) rescue nil

    if hash.nil?
      raise Coinmux::Error, "Unable to post to #{path}: invalid JSON response"
    elsif hash['error']
      raise Coinmux::Error, "Unable to post to #{path}: #{hash['error']} (#{hash['detail']})"
    end

    hash
  end

  def webbtc_get_bin(path)
    http_facade.get(config_facade.webbtc_host, path)
  end

  def webbtc_get_json(path)
    result = http_facade.get(config_facade.webbtc_host, path)
    hash = JSON.parse(result) rescue nil

    if hash.nil?
      raise Coinmux::Error, "Unable to parse JSON"
    elsif hash['error']
      raise Coinmux::Error, "Invalid request: #{hash['error']}"
    end

    hash
  end
end