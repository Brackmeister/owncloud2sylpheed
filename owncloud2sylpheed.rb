require 'rubygems'
require 'net/dav'
require 'vpim'
require 'parseconfig'
require 'pathname'

# some of the gems don't work without this
class String
  alias_method :each, :each_line
end

# some crude method to ask the user for the necessary settings if no config file was found yet
def inittconf(conffile)
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

# try to read settings from config file. If not present, ask the user for them
conffile = Pathname.new(Dir.home + "/.config/owncloud2sylpheed")
if conffile.exist?
  config = ParseConfig.new(conffile)
  # TODO: check if mandatory settings are present
else
  config = inittconf(conffile)
end

url  = config['url']
user = config['user']
pasw = config['pass']

# connect to the owncloud server via WebDAV
dav = Net::DAV.new(url, :curl => false)
dav.verify_server = false # Ignore server verification
dav.credentials(user, pasw)

# find all vcard entries and add those to the addresses array that contain an email
addresses = []
dav.find('.',:recursive=>true,:suppress_errors=>true,:filename=>/\.vcf$/) do | item |
  cards = Vpim::Vcard.decode(item.content)

  cards.each do |card|
    if not (card.email.nil? or card.email.empty? ) then
#      puts "Mail=#{card.email}"
      addresses.push(card)
    end
  end
end

# create an XML address-book file suitable for sylpheed for all entries in addresses
builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
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

# for the time being, simply output the result to STDOUT
puts builder.to_xml
# TODO: parse the sylpheed address book list for an address book called "owncloud" and overwrite that. Create it if it doesn't exist yet
