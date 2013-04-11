require 'main'
require 'rest-client'
require 'nokogiri'
require 'typhoeus'

class PastaEval
  attr_accessor :url, :xsd

  def initialize
    super
    Dir.chdir("./lib/eml") do
      @xsd = Nokogiri::XML::Schema(File.read("eml.xsd"))
    end
  end


  def evaluate(production=nil, timeout_val = 30)
    @time_out_value = timeout_val
    if File.exists?('index.html')
      File.unlink('index.html')
    end
    @server = 'https://pasta-s.lternet.edu'
    if production.given?
      @server = 'https://pasta.lternet.edu'
    end

    #get url
    response = Typhoeus.get(url, :timeout => 3000)
    doc = Nokogiri::XML(response.response_body)
    docs = doc.xpath('//documentURL')
    if docs.empty?
      evaluate_document(url)
    else
      docs.each do |eml_url|
        clear_scope_id_rev
        evaluate_document(eml_url.text)
      end
    end
  end

  def evaluate_document(eml_url)
    print "#{eml_url} "
    response = Typhoeus.get(eml_url, :timeout => 3000)
    eml_doc = Nokogiri::XML(response.response_body)
    if xsd.validate(eml_doc)

      set_scope_id_rev(eml_doc)

      # try to evaluate
      response = Typhoeus.post("#{@server}/package/evaluate/eml",
                               :body  => eml_doc.to_s,
                               :headers => {'Content-Type' => "application/xml; charset=utf-8"})
      @transaction_id = response.response_body
      print "#{@scope}.#{@identifier}.#{@rev} "
      print @transaction_id

      if @transaction_id.empty?
        puts "failed to submit"
      else
        #poll for completion
        timeout_at = Time.now + 60 * @time_out_value
        loop do
          sleep 10
          print '.'

          break if pasta_success?
          break if pasta_errors?

          break if Time.now > timeout_at
        end

        if @errors
          puts @errors
          @errors = nil
        else
          if @report
            print_summary
            save_results

            @report = nil
          else
            puts ' timeout'
          end
        end
      end
    else
      puts 'Error: not an eml document'
    end
  end

  def valids
    @report.search('//qr:status[contains(text(), "valid")]')
  end

  def warns
    @report.search('//qr:status[contains(text(), "warn")]/..')
  end

  def infos
    @report.search('//qr:status[contains(text(), "info")]/..')
  end

  def errors
    @report.search('//qr:status[contains(text(), "error")]/..')
  end

  def save_results

    if File.exists?('index.html')
      index = Nokogiri::HTML(open('index.html'))
    else
      index = Nokogiri::HTML('<html><head><link href="bootstrap/css/bootstrap.min.css" rel="stylesheet"></link></head><body><ul id="docs"></ul></body>')
      File.write('index.html', index)
    end
    # append a line to the index file
    line = index.at_css('#docs')
    stanza = Nokogiri::XML::Builder.with(line) do |html|
      html.li {
        html.text " #{@scope}-#{@identifier}-#{@rev} valid: #{valids.count} info: #{infos.count} warn: #{warns.count} error: #{errors.count}"
        html.h3 "Warns" if warns.count > 0
        html.ul {
          warns.each do |warn|
          html.li {
            html.text "Name: #{warn.css('name')}"
            html.text "Expected: #{warn.css('expected')}"
            html.text "Found: #{warn.css('found')}"
          }
          end
        }
        html.h3 "Errors" if errors.count > 0
      }
    end

    File.write('index.html', index)

    File.open("#{@scope}-#{@identifier}-#{@rev}.xml",'w') do |file|
      file.write @report
    end
  end

  def print_summary
    puts " valid: #{valids.count} info: #{infos.count} warn: #{warns.count} error: #{errors.count}"
  end

  def clear_scope_id_rev
    @scope = @identifier = @rev = nil
  end

  def set_scope_id_rev(doc)
    package_id = doc.root['packageId']
    if package_id
      @scope, @identifier, @rev = package_id.split(/\./)
    end
  end

  def pasta_success?
    response = Typhoeus.get("#{@server}/package/evaluate/report/eml/#{@scope}/#{@identifier}/#{@rev}/#{@transaction_id}")
    @report = Nokogiri::XML(response.response_body) if response.success?
    response.success?
  end

  def pasta_errors?
    response = Typhoeus.get("#{@server}/package/error/#{@scope}/#{@identifier}/#{@rev}/#{@transaction_id}")
    @errors = response.response_body if response.success?

    response.success?
  end
end

Main {
  argument 'url'
  option('p') { description 'to use the production server' }
  option('debug') { description 'print debugging statements' }
  option('timeout') {
    argument :optional
    cast :integer
    default 30
    description 'timeout in minutes'
  }

  def run
    if params['debug'].given?
      Typhoeus::Config.verbose = true
    end

    pusher = PastaEval.new
    pusher.url = params['url'].value
    pusher.evaluate(params['p'],params['timeout'].value)
    puts "done, now get back to work!"
  end
}

