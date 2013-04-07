#!/usr/bin/env ruby
require 'rubygems' if RUBY_VERSION < '1.9.0'
require "net/https"
require 'json'
require 'settings'
require 'cli'
require 'rainbow'
require 'uri'

module SensuCli
  class Core
    #
    # CLI can be anything assuming you can pass these paramaters
    # Field names were derived from the sensu source/documentation.
    # cli = {
    #   :command => 'client',
    #   :method => 'Get',
    #   :flags => {:name => 'ntp-check',
    #              :path => '/keepalive/i-asesew',
    #              :client => 'i-23412412',
    #              :check => 'ntp-check'}
    # }

    def initialize
      cli = Cli.opts
      @settings = Settings.load_file
      request(cli)
    end

    def request(cli)
      case cli[:command]
      when 'clients'
        if cli[:fields][:name]
          @api = {:path => "/client/#{cli[:fields][:name]}"}
        else
          @api = {:path => '/clients'}
        end
      when 'info'
        @api = {:path => '/info'}
      when 'stashes'
        if cli[:fields][:path]
          @api = {:path => "/stashes/#{cli[:fields][:path]}"}
        else
          @api = {:path => '/stashes'}
        end
      when 'checks'
        if cli[:fields][:name] && cli[:fields][:check]
          @api = {:path => "/check/#{cli[:fields][:name]}/#{cli[:fields][:check]}"}
        elsif cli[:fields][:name]
          @api = {:path => "/check/#{cli[:fields][:name]}"}
        else
          @api = {:path => '/checks'}
        end
      when 'events'
        if cli[:fields][:client] && cli[:fields][:check]
          @api = {:path => "/events/#{cli[:fields][:client]}/#{cli[:fields][:check]}"}
        elsif cli[:fields][:client]
          @api = {:path => "/events/#{cli[:fields][:client]}"}
        else
          @api = {:path => "/events"}
        end
      when 'resolve'
        payload = {:client => cli[:fields][:client], :check => cli[:fields][:check]}.to_json
        @api = {:path => "/event/resolve", :payload => payload}
      when 'silence'
        payload = {:timestamp => Time.now.to_i}.to_json
        if cli[:fields][:client] && cli[:fields][:check]
          @api = {:path => "/stashes/silence/#{cli[:fields][:client]}/#{cli[:fields][:check]}", :payload => payload}
        else
          @api = {:path => "/stashes/silence/#{cli[:fields][:client]}", :payload => payload}
        end
      end
      @api.merge!({:method => cli[:method], :command => cli[:command]})
      pretty(api)
    end

    def api_request
      http = Net::HTTP.new(@settings[:host], @settings[:port])
      http.read_timeout = 15
      http.open_timeout = 5
      if @settings[:ssl]
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      case @api[:method]
      when 'Get'
        req =  Net::HTTP::Get.new(@api[:path])
      when 'Delete'
        req =  Net::HTTP::Delete.new(@api[:path])
      when 'Post'
        req =  Net::HTTP::Post.new(@api[:path],initheader = {'Content-Type' =>'application/json'})
        req.body = @api[:payload]
      end
      begin
        http.request(req)
      rescue Timeout::Error
        puts "HTTP connection timed out".color(:red)
        exit
      end
    end

    def api
      res = api_request
      msg = response_codes(res)
      if res.code != '200'
        exit
      else
        msg
      end
    end

    def response_codes(res)
      case res.code
      when '200'
        JSON.parse(res.body)
      when '201'
        puts "The stash has been created."
      when '202'
        puts "The item was submitted for processing."
      when '204'
        puts "The item was successfully deleted."
      when '400'
        puts "The payload is malformed".color(:red)
      when '404'
        puts "The #{@api[:command]} did not exist".color(:cyan)
      else
        puts "There was an error while trying to complete your request. Response code: #{res.code}".color(:red)
      end
    end

    def pretty(res)
      if !res.empty?
        res.each do |item|
          puts "----"
          if item.is_a?(Hash)
            item.each do |key,value|
              puts "#{key}:  ".color(:cyan) + "#{value}".color(:green)
            end
          elsif item.is_a?(Array)
              item.each do |key|
                puts "#{key}:  ".color(:cyan)
              end
          else
            puts item.color(:cyan)
          end
        end
      else
        puts "no values for this request".color(:cyan)
      end
    end

  end
end
