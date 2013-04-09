require 'main'
require 'rest-client'
require 'nokogiri'
require 'open-uri'
require 'typhoeus'

class PastaEval
  attr_accessor :url

  def evaluate(production=nil, timeout_value = 30)
    @server = 'https://pasta-s.lternet.edu'
    if production.given?
      @server = 'https://pasta.lternet.edu'
    end

    #get url
    doc = Nokogiri::XML(open(url))
    doc.xpath('//documentURL').each do |eml_url|
      print "#{eml_url.text} "
      eml_doc = Nokogiri::XML(open(eml_url))

      set_scope_id_rev(eml_url)

      # try to evaluate
      response = Typhoeus.post("#{@server}/package/evaluate/eml",
                               :body  => eml_doc.to_s,
                               :headers => {'Content-Type' => "application/xml; charset=utf-8"})
      @transaction_id = response.response_body

      #poll for completion
      timeout_at = Time.now + 60 * timeout_value
      loop do
        sleep 5
        print '.'

        break if pasta_success?
        break if pasta_errors?

        break if Time.now > timeout_at
      end

      if @errors
        puts @errors
        @errors = nil
        next
      end

      if @report
        File.write('response.xml',@report)

        print_summary

        # remove valid checks
        @report.search('//qr:status[contains(text(), "valid")]/..').each do |node|
          node.remove
        end

        File.open("#{@scope}-#{@identifier}-#{@rev}",'w') do |file|
          file.write @report
        end
        @report = nil
      else
        puts ' timeout'
      end
    end
  end

  def valids
    @report.search('//qr:status[contains(text(), "valid")]')
  end

  def warns
    @report.search('//qr:status[contains(text(), "warn")]')
  end

  def infos
    @report.search('//qr:status[contains(text(), "info")]')
  end

  def errors
    @report.search('//qr:status[contains(text(), "error")]')
  end

  def print_summary
    puts " valid: #{valids.count} info: #{infos.count} warn: #{warns.count} error: #{errors.count}"
  end

  def set_scope_id_rev(fragment)
    info = fragment.parent
    @scope = info.search('scope').text
    @identifier = info.search('identifier').text
    @rev = info.search('revision').text
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

