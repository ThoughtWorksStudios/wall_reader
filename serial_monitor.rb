require 'rubygems'
require 'serialport'

require 'date'

require "net/http"
require "uri"

class CardRFID 
  
  attr_reader :card_number
  
  def initialize(rfid, card_number, values)
    @rfid = rfid
    @card_number = card_number
    @current_done_value = 0
    @values = values
  end
  
  def next_property_value
    @values[@current_done_value]
  end
  
  def read?(read_rfid)
    if @rfid == read_rfid.to_i
      @current_done_value = @current_done_value + 1
      true
    end
  end
  
end

class Request

  def initialize(options)
    @username = options[:username] 
    @password = options[:password]
    @base_url = "http://#{options[:host]}:#{options[:port]}"
  end
  
  def put(url, data)
    uri = URI.parse("#{@base_url}#{url}")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Put.new(uri.request_uri)
    request.basic_auth(@username, @password)
    request.set_form_data(data)
    http.request(request)
  end
  
  def post(url, data)
    uri = URI.parse("#{@base_url}#{url}")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri.request_uri)
    request.basic_auth(@username, @password)
    request.set_form_data(data)
    http.request(request)
  end
  
end

class Mingle
  
  attr_reader :values
  
  def initialize
    @request = Request.new(:username => "admin", :password => "p", :host => "localhost", :port => "8080")
    @project = "cow_farm"
    @property_name = "Status"
    @values = ["New", "In Progress", "Done"]
  end
  
  def update_status(card)
    @request.put("/api/v2/projects/#{@project}/cards/#{card.card_number}.xml", {"card[properties][][name]" => @property_name, 
                    "card[properties][][value]" => card.next_property_value })
  end

  def create_card
    create_card_type = "Story"
    create_card_name = "CREATED BY THE READER"
    
    response = @request.post("/api/v2/projects/#{@project}/cards.xml", {  "card[name]" => create_card_name, 
                                      "card[card_type_name]" => create_card_type, 
                                      "card[properties][][name]" => @property_name, 
                                      "card[properties][][value]" => @values.first 
                                    })
    /cards\/(.*)\.xml/.match(response['Location'])[1]
  end
  
end

class MingleCardReader
  
  def initialize 
    @mingle = Mingle.new
    @cards = []
    @sp = SerialPort.new(ARGV[0], 9600, 8, 1, SerialPort::NONE)
  end
  
  def monitor
    while (i = @sp.gets) do

      puts "got #{i}"
      
      if(clean_rfid_input(i).length == 10)
        
        read_card = @cards.find { |c| c.read?(i) }
      
        unless read_card.nil?
          update_card(read_card)
        else
          associate_card(i)
        end
      
        print_to_reader("scan a card...")
        
      end        
    end
  end
  
  private
  
  def update_card(read_card)
    @mingle.update_status(read_card)
    print_to_reader("updated card #{read_card.card_number}")
    print_to_reader("to #{read_card.next_property_value}")
  end
  
  def associate_card(rfid)
    print_to_reader "UNKNOWN"
    new_card_number = @sp.gets.chomp
  
    if(new_card_number == "0")
      new_card_number = @mingle.create_card
      print_to_reader "created #{new_card_number}", 3
    else
      print_to_reader "set to #{new_card_number}", 3
    end
  
    @cards << CardRFID.new(clean_rfid_input(rfid).to_i, new_card_number, @mingle.values)
  end
  
  def clean_rfid_input(rfid)
    rfid.chomp.gsub(/[^0-9]+/, '')
  end
  
  def print_to_reader(message, delay=1)
    @sp.print(message)
    sleep delay
  end

end 
  
begin     
  while TRUE do
    reader = MingleCardReader.new
    reader.monitor        
  end     
rescue Exception => e
  puts "ERROR: #{e.inspect}"
  puts e.backtrace
end