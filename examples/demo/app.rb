require 'sinatra/base'
require 'doozque'
require 'job'

module Demo
  class App < Sinatra::Base
    get '/' do
      info = Doozque.info
      out = "<html><head><title>Doozque Demo</title></head><body>"
      out << "<p>"
      out << "There are #{info[:pending]} pending and "
      out << "#{info[:processed]} processed jobs across #{info[:queues]} queues."
      out << "</p>"
      out << '<form method="POST">'
      out << '<input type="submit" value="Create New Job"/>'
      out << '&nbsp;&nbsp;<a href="/doozque/">View Doozque</a>'
      out << '</form>'
      
       out << "<form action='/failing' method='POST''>"
       out << '<input type="submit" value="Create Failing New Job"/>'
       out << '&nbsp;&nbsp;<a href="/doozque/">View Doozque</a>'
       out << '</form>'
      
      out << "</body></html>"
      out
    end

    post '/' do
      Doozque.enqueue(Job, params)
      redirect "/"
    end
    
    post '/failing' do 
      Doozque.enqueue(FailingJob, params)
      redirect "/"
    end
  end
end
