require 'nokogiri'
require 'yaml'
require 'typhoeus'

#TODO report/doi/eml/{scope}/{identifier}/{revision}
#curl -i -X GET https://pasta.lternet.edu/package/report/doi/eml/knb-lter-lno/1/1

class PastaEval
  attr_accessor :url
  attr_accessor :upload
  attr_accessor :cache
  attr_accessor :file_name

  def initialize(production=nil)
    if File.exists?('credentials.yaml')
      credentials = File.open('credentials.yaml') {|y| YAML::load(y)}
      @user       = "uid=#{credentials['username']},o=LTER,dc=ecoinformatics,dc=org:#{credentials['password']}"
    end

    @server       = 'https://pasta-s.lternet.edu'
    if production.given?
      @server     = 'https://pasta.lternet.edu'
    end
  end

  def delete_all
    response = Typhoeus.get("#{@server}/package/eml/knb-lter-kbs",
                             :userpwd=> @user)
    response.body.each_line do |id|
      delete(id.to_i)
    end

  end
  def delete(id)
    response = Typhoeus.get("#{@server}/package/eml/knb-lter-kbs/#{id}", userpwd: @user)
    response.body.each_line do |i|
      response = Typhoeus.delete("#{@server}/package/eml/knb-lter-kbs/#{id}",
                                 :userpwd=> @user)
      puts(response.body)
    end
  end


  def evaluate(timeout_val = 30)
    @time_out_value = timeout_val
    if File.exists?('index.html')
      File.unlink('index.html')
    end

    #get url
    response = Typhoeus.get(url, :timeout => 3000)
    doc = Nokogiri::XML(response.response_body)
    docs = doc.xpath('//documentURL')
    if docs.empty?
      evaluate_document(url)
    else
      docs.each_with_index do |eml_url, index|
        print "#{index} "
        clear_scope_id_rev
        evaluate_document(eml_url.text)
        sleep(10)
      end
    end
  end

  def evaluate_document(eml_url)

    print "#{eml_url} "
    response = Typhoeus.get(eml_url, :timeout => 3000)
    eml_doc = Nokogiri::XML(response.response_body)
    if eml_doc.root.first

      set_scope_id_rev(eml_doc)
      print " #{@scope}.#{@identifier}.#{@rev} "

      # see if it is already in PASTA
      if document_version_exists?
        print " already in PASTA"
        return
      end

      # if cached download the data files and modify the eml
      if cached
        hostname = `hostname -f`
        hostname.chomp!
        datatables = eml_doc.xpath("//dataset/dataTable").each do |table|
          @file_name = "data/cached" + table.attribute('id').text.gsub(/\//,'-') + ".csv"
          url = table.xpath("physical/distribution/online/url").first
          downloaded_file = File.open file_name, 'wb'
          request = Typhoeus::Request.new(url.text)
          request.on_headers do |response|
            if response.code != 200
              raise "Request failed"
            end
          end
          request.on_body do |chunk|
            downloaded_file.write(chunk)
          end
          request.on_complete do |response|
            downloaded_file.close
            # Note that response.body is ""
          end
          request.run
          url.content = "http://#{hostname}:2015/#{file_name}"
        end
      end

      # try to evaluate
      response = Typhoeus.post("#{@server}/package/evaluate/eml",
                               :userpwd=> @user,
                               :body  => eml_doc.to_s,
                               :headers => {'Content-Type' => "application/xml; charset=utf-8"})
      @transaction_id = response.response_body
      print @transaction_id

      wait_for_eval_completion(eml_doc)

      File.unlink @file_name
    else
      puts 'Error: not an eml document'
    end
  end

  def wait_for_eval_completion(eml_doc)
    if @transaction_id.empty?
      puts "failed to submit"
    else
      #poll for completion
      timeout_at = Time.now + 60 * @time_out_value

      while !completed?(timeout_at) do
        sleep 10
        print '.'
      end 

      if @errors
        print_errors
      else
        if @report
          print_summary
          #TODO this should be after the function returns
          if upload && errors.count == 0
            submit_document(eml_doc) 
          end
        else
          puts ' timeout'
        end
      end
    end
  end

  def wait_for_completion(eml_doc)
    if @transaction_id.empty?
      puts "failed to submit"
    else
      #poll for completion
      timeout_at = Time.now + 60 * @time_out_value

      while !completed?(timeout_at) do
        sleep 10
        print '.'
      end 

      if @errors
        print_errors
      elsif timeout_at < Time.now()
        puts ' timeout'
      else
        puts ' done'
      end
    end
  end

  def submit_document(doc)
    if document_exists?
      update_document(doc)
    else
      submit_new_document(doc)
    end
  end

  def document_exists?
    document_exists = Typhoeus.get("#{@server}/package/eml/#{@scope}/#{@identifier}") 
    document_exists.success?
  end

  def document_version_exists?
    document_exists = Typhoeus.get("#{@server}/package/eml/#{@scope}/#{@identifier}/#{@rev}") 
    document_exists.success?
  end


  def submit_new_document(doc)
    response = Typhoeus.post("#{@server}/package/eml",
                             :userpwd=> @user,
                             :body  => doc.to_s,
                             :headers => {'Content-Type' => "application/xml; charset=utf-8"})
    @transaction_id = response.response_body
    print @transaction_id
    wait_for_completion(doc)
  end

  def update_document(doc)
    response = Typhoeus.put("#{@server}/package/eml/#{@scope}/#{@identifier}",
                             :userpwd=> @user,
                             :body  => doc.to_s,
                             :headers => {'Content-Type' => "application/xml; charset=utf-8"})
    @transaction_id = response.response_body
    print @transaction_id
    wait_for_completion(doc)
  end

  def completed?(timeout_at)
    pasta_success? || pasta_errors? || document_version_exists? || Time.now > timeout_at
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

  def print_errors
    puts @errors
  end

  def print_summary
    pasta_success?
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
    @report = nil
    response = Typhoeus.get("#{@server}/package/evaluate/report/eml/#{@transaction_id}", :userpwd => @user)
    if response.success?
      @report = Nokogiri::XML(response.response_body) if response.success?
      if errors.count > 0
        File.open(@transaction_id, 'w') {|f| f.write @report}
      end
    end
    response.success?
  end

  def pasta_errors?
    @errors = nil
    response = Typhoeus.get("#{@server}/package/error/eml/#{@transaction_id}", :userpwd => @user)
    @errors = response.response_body if response.success?

    response.success?
  end
end
