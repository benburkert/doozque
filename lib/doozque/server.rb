require 'sinatra/base'
require 'erb'
require 'doozque'
require 'doozque/version'
require 'time'

module Doozque
  class Server < Sinatra::Base
    dir = File.dirname(File.expand_path(__FILE__))

    set :views,  "#{dir}/server/views"
    set :public, "#{dir}/server/public"
    set :static, true

    helpers do
      include Rack::Utils
      alias_method :h, :escape_html

      def current_section
        url_path request.path_info.sub('/','').split('/')[0].downcase
      end

      def current_page
        url_path request.path_info.sub('/','')
      end

      def url_path(*path_parts)
        [ path_prefix, path_parts ].join("/").squeeze('/')
      end
      alias_method :u, :url_path

      def path_prefix
        request.env['SCRIPT_NAME']
      end

      def class_if_current(path = '')
        'class="current"' if current_page[0, path.size] == path
      end

      def tab(name)
        dname = name.to_s.downcase
        path = url_path(dname)
        "<li #{class_if_current(path)}><a href='#{path}'>#{name}</a></li>"
      end

      def tabs
        Doozque::Server.tabs
      end

      def redis_get_size(key)
        case Doozque.redis.type(key)
        when 'none'
          []
        when 'list'
          Doozque.redis.llen(key)
        when 'set'
          Doozque.redis.scard(key)
        when 'string'
          Doozque.redis.get(key).length
        when 'zset'
          Doozque.redis.zcard(key)
        end
      end

      def redis_get_value_as_array(key, start=0)
        case Doozque.redis.type(key)
        when 'none'
          []
        when 'list'
          Doozque.redis.lrange(key, start, start + 20)
        when 'set'
          Doozque.redis.smembers(key)[start..(start + 20)]
        when 'string'
          [Doozque.redis.get(key)]
        when 'zset'
          Doozque.redis.zrange(key, start, start + 20)
        end
      end

      def show_args(args)
        Array(args).map { |a| a.inspect }.join("\n")
      end

      def worker_hosts
        @worker_hosts ||= worker_hosts!
      end

      def worker_hosts!
        hosts = Hash.new { [] }

        Doozque.workers.each do |worker|
          host, _ = worker.to_s.split(':')
          hosts[host] += [worker.to_s]
        end

        hosts
      end

      def partial?
        @partial
      end

      def partial(template, local_vars = {})
        @partial = true
        erb(template.to_sym, {:layout => false}, local_vars)
      ensure
        @partial = false
      end

      def poll
        if @polling
          text = "Last Updated: #{Time.now.strftime("%H:%M:%S")}"
        else
          text = "<a href='#{u(request.path_info)}.poll' rel='poll'>Live Poll</a>"
        end
        "<p class='poll'>#{text}</p>"
      end

    end

    def show(page, layout = true)
      begin
        erb page.to_sym, {:layout => layout}, :doozque => Doozque
      rescue Errno::ECONNREFUSED
        erb :error, {:layout => false}, :error => "Can't connect to Redis! (#{Doozque.redis_id})"
      end
    end
    
    def show_for_polling(page)
      content_type "text/html"
      @polling = true
      show(page.to_sym, false).gsub(/\s{1,}/, ' ')
    end

    # to make things easier on ourselves
    get "/?" do
      redirect url_path(:overview)
    end
    
    %w( overview workers ).each do |page|
      get "/#{page}.poll" do
        show_for_polling(page)
      end
      
      get "/#{page}/:id.poll" do
        show_for_polling(page)
      end
    end

    %w( overview queues working workers key ).each do |page|
      get "/#{page}" do
        show page
      end

      get "/#{page}/:id" do
        show page
      end
    end

    post "/queues/:id/remove" do
      Doozque.remove_queue(params[:id])
      redirect u('queues')
    end

    get "/failed" do
      if Doozque::Failure.url
        redirect Doozque::Failure.url
      else
        show :failed
      end
    end

    post "/failed/clear" do
      Doozque::Failure.clear
      redirect u('failed')
    end

    get "/failed/requeue/:index" do
      Doozque::Failure.requeue(params[:index])
      if request.xhr?
        return Doozque::Failure.all(params[:index])['retried_at']
      else
        redirect u('failed')
      end
    end

    get "/failed/remove/:index" do
      Doozque::Failure.remove(params[:index])
      redirect u('failed')
    end

    get "/stats" do
      redirect url_path("/stats/doozque")
    end

    get "/stats/:id" do
      show :stats
    end

    get "/stats/keys/:key" do
      show :stats
    end

    get "/stats.txt" do
      info = Doozque.info

      stats = []
      stats << "doozque.pending=#{info[:pending]}"
      stats << "doozque.processed+=#{info[:processed]}"
      stats << "doozque.failed+=#{info[:failed]}"
      stats << "doozque.workers=#{info[:workers]}"
      stats << "doozque.working=#{info[:working]}"

      Doozque.queues.each do |queue|
        stats << "queues.#{queue}=#{Doozque.size(queue)}"
      end

      content_type 'text/html'
      stats.join "\n"
    end

    def doozque
      Doozque
    end

    def self.tabs
      @tabs ||= ["Overview", "Working", "Failed", "Queues", "Workers", "Stats"]
    end
  end
end
