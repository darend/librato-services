module Librato
  module Services
    class App < Sinatra::Base
      configure :production do
        set :raise_errors, true

        if ENV['NEW_RELIC_APPNAME']
          # Use New Relic RPM
          require "newrelic_rpm"
        end
      end

      helpers do
        include Librato::Services::Authentication
      end

      before do
        if ENV["LIBRATO_SERVICES_CREDS"]
          authenticate
        end
      end

      def self.service(svc)
        post "/services/#{svc.hook_name}/:event.:format" do
          halt 400 unless params[:format].to_s == "json"
          begin
            body = json_decode(request.body.read)

            halt 400 unless body

            payload = {
              :alert => body['alert'],
              :metric => body['metric'],
              :measurement => body['measurement'],
              :trigger_time => body['trigger_time']
            }

            settings = HashWithIndifferentAccess.new(body['settings'])
            payload = HashWithIndifferentAccess.new(payload)

            if svc.receive(:alert, settings, payload)
              status 200
              ''
            else
              status 404
              status "#{svc.hook_name} Service could not process request"
            end

          rescue Service::ConfigurationError => e
            status 400
            e.message
          end
        end

        get '/' do
          'ok'
        end

        def json_decode(value)
          Yajl::Parser.parse(value, :check_utf8 => false)
        end

        def json_encode(value)
          Yajl::Encoder.encode(value)
        end

        def report_exception(e)
          $stderr.puts "Error: #{e.class}: #{e.message}"
          $stderr.puts "\t#{e.backtrace.join("\n\t")}"

          # Let exception middleware catch this
          raise e
        end
      end
    end
  end
end
