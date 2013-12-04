require 'swt'
require 'glimmer'

class Coin2Coin::Application
  include Glimmer

  include_package 'org.eclipse.swt'
  include_package 'org.eclipse.swt.widgets'
  include_package 'org.eclipse.swt.layout'
  include_package 'org.eclipse.jface.viewers'
  
  def initialize
    @shell = shell {
      text "Coin2Coin - Decentralized, Trustless, Anonymous and Open Bitcoin Mixer"
      
      tab_folder {
        tab_item {
          text "Home"
          home_tab_item
        }
        tab_item {
          text "CoinJoins"
          coinjoins_tab_item
        }
      }
    }
  end
  
  def current_coin_join
    @current_coin_join ||= Coin2Coin::CoinJoin.new
  end
  
  def home_tab_item
    composite {
      label {
        text "CoinJoins allow you to anonimize your Bitcoins by\ncombining them with other users on the Bitcoin network."
      }
      label {
        text "To do this, this application needs access to your\nprivate keys. This information is never sent over the\nInternet and is never even stored to disk."
      }
    }
    composite {
      layout GridLayout.new(2, false)
      label {
        text "Add Bitcoin Inputs"
      }
    }
    coin_join_transaction
  end
  
  def new_input
    @new_input ||= Coin2Coin::Input.new
  end
  
  def coin_join_transaction
    group {
      text "CoinJoin Transaction"
      layout_data build_fill_grid_data
      
      group {
        text "New Inputs"
        layout_data build_fill_grid_data
        composite {
          layout_data build_fill_grid_data
          layout GridLayout.new(3, false)
          label { text "Private Key" }
          text {
            layout_data build_fill_grid_data
            text bind(new_input, :private_key)
          }
          button {
            text "Add"
            on_widget_selected {
              input = Coin2Coin::Input.find_by_private_key(new_input.private_key)
              if input.valid?
                current_coin_join.inputs << input
                
                new_input.bitcoin_address = nil
                new_input.private_key = nil
                new_input.public_key = nil
              else
                raise "TODO"
              end
            }
          }
        }
      }
      composite {
        table {
          grid_data = GridData.new(:fill.swt_constant, :fill.swt_constant, true, true)
          grid_data.heightHint = 100
          layout_data grid_data
          table_column {
            text "Bitcoin Address"
            width 360
          }
          table_column {
            text "Amount"
            width 80
          }
          items bind(current_coin_join, :inputs), column_properties(:bitcoin_address, :amount)
        }
      }
    }
    button {
      text "Create CoinJoin (Needs to be big and have image)"
      enabled bind(current_coin_join, :valid)
    }
  end
  
  def coinjoins_tab_item
  end
  
  def start
    @shell.widget.open
    until @shell.widget.isDisposed
      @shell.display.sleep unless @shell.display.readAndDispatch
    end
    @shell.display.dispose
    
    # @shell.open
  end
  
  private
  
  def build_fill_grid_data
    grid_data = GridData.new
    grid_data.horizontalAlignment = SWT::FILL
    grid_data.grabExcessHorizontalSpace = true
    
    grid_data
  end
  
end