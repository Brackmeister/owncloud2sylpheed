require 'rubygems'
require 'net/dav'
require 'vpim'
require 'parseconfig'
require 'pathname'

### some of the gems don't work without this
class String
  alias_method :each, :each_line
end

### class dealing with the configuration file/values
class MyConfig
  # constructor
  def initialize(conffile=nil)
    if conffile == nil
      @conffile = Dir.home + "/.config/owncloud2sylpheed" 
    else
      @conffile = conffile
    end
    readConf
  end

  def readConf
    pn = Pathname.new(@conffile)
    if pn.exist?
      @config = ParseConfig.new(pn)
      @config = initConf(pn) if not checkConf
    else
      @config = initConf(pn)
    end
  end

  # some crude method to ask the user for the necessary settings if no config file was found yet
  # TODO: use some nice GUI
  def initConf(conffile)
    puts "Enter hostname:"
    host = gets.chomp
    puts "Use SSL (Y/N)?"
    ssl = gets.chomp
    puts "Enter path (default: owncloud)"
    path = gets.chomp
    path = "owncloud" if path.empty?
    puts "Enter username:"
    user = gets.chomp
    puts "Enter password:"
    pass = gets.chomp
    # TODO: encrypt password for a little bit of security. Ideally use kdewallet or the like.

    if ssl.upcase == 'Y'
      fullurl = "https"
    else 
      fullurl = "http"
    end
    fullurl += "://"+host+"/"+path+"/remote.php/carddav/addressbooks/"+user+"/contacts"

    puts "Using URL #{fullurl}."

    conf = ParseConfig.new
    conf.add('url',  fullurl)
    conf.add('user', user)
    conf.add('pass', pass)

    file = File.open(conffile, 'w', 0600)
    conf.write(file)
    file.close

    return conf
  end

  # mandatory config values must be present and not empty
  def checkConf
    return false if @config['url'].nil? or @config['url'].empty?
    return false if @config['user'].nil? or @config['url'].empty?
    return false if @config['pass'].nil? or @config['url'].empty?
    return true
  end

  # accessor
  def config
    return @config
  end

end # class MyConfig

### class to connect to owncloud and fetch data
class MyWebdav
  # constructor
  def initialize(myconfig)
    # connect to the owncloud server via WebDAV
    @dav = Net::DAV.new(myconfig.config['url'], :curl => false)
    @dav.verify_server = false # Ignore server verification
    @dav.credentials(myconfig.config['user'], myconfig.config['pass'])
  end

  # find all vcard entries and add those to the addresses array that contain an email
  def findEmails
    addresses = []
    @dav.find('.',:recursive=>true,:suppress_errors=>true,:filename=>/\.vcf$/) do | item |
      cards = Vpim::Vcard.decode(item.content)

      cards.each do |card|
        if not (card.email.nil? or card.email.empty? ) then
#          puts "Mail=#{card.email}"
          addresses.push(card)
        end
      end
    end
    return addresses
  end

end # class MyWebdav

### class to create the XML structure for the addresses
class MyXML
  #constructor
  def initialize(addresses)
    # create an XML address-book file suitable for sylpheed for all entries in addresses
    @builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
      xml.send(:"address-book", :name => "owncloud") {
        addresses.each do |card|
          xml.person(:uid => card.value('uid'), # FIXME sylpheed uids look different but it seems to work anyway
                     :"first-name" => card.name.given, 
                     :"last-name" => card.name.family, 
                     :"nick-name" => "", 
                     :cn => card.name.formatted) {
            xml.send(:"address-list") {
              xml.address(:uid => card.value('uid')+"e", # FIXME the "e" is for "email" but we don't need anything more sophisticated
                          :alias => "",
                          :email => card.email,
                          :remarks => "")
            }
            xml.send(:"attribute-list") {
            }
          }
        end
      }
    end
  end

  # output XML to STDOUT
  def print
    puts @builder.to_xml
  end

  # write the xml to the sylpheed configuration directory as addressbook with name "owncloud"
  def writeAddressbook
    addressbooklist = Pathname.new(Dir.home + "/.sylpheed-2.0/addrbook--index.xml")
    if addressbooklist.exist?
      input = Nokogiri::XML(File.new(addressbooklist))
      owncloudaddressbook = input.root.xpath('//book[@name="owncloud"]/@file')
      if owncloudaddressbook.nil? or owncloudaddressbook.empty?
        filename = addAddressbook(addressbooklist)
      else
        filename = owncloudaddressbook.to_s
      end
      File.open(Dir.home + "/.sylpheed-2.0/" + filename , 'w', 0600) {|f| f.write(@builder.to_xml) }
    else
      $stderr.puts "Error reading #{Pathname}"
    end
  end

  # when no book named "owncloud" exists, create it
  def addAddressbook(indexfile)
    input = Nokogiri::XML(File.new(indexfile))
    max = 0
    input.root.xpath('//book').each do |node|
      number = /addrbook-0*([1-9][0-9]*).xml/.match(node['file'])[1].to_i
      max = number if number > max
    end
    newaddressbookfile = "addrbook-%06d.xml" % [max+1]
    node = Nokogiri::XML::Node.new "book", input
    node['name'] = 'owncloud'
    node['file'] = newaddressbookfile
    input.root.xpath('book_list')[0].add_child(node)

    File.open(indexfile, 'w') { |f| f.write(input.to_xml) }

    return newaddressbookfile
  end

end # class MyXML

### "main" program starts here
# TODO: some kind of argument handling like --help, --verbose, --version etc.
myconfig = MyConfig.new

mywebdav = MyWebdav.new(myconfig)
addresses = mywebdav.findEmails

myxml = MyXML.new(addresses)
myxml.writeAddressbook
