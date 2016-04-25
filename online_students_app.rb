require 'bundler/setup'
require 'wolf_core'

class OnlineStudentsApp < WolfCore::App
  set :root, File.dirname(__FILE__)
  self.setup

  set :enrollment_terms, get_enrollment_terms

  use WolfCore::AuthFilter

  get '/' do
    slim :index
  end

  post '/' do
    params['user_email'] = session['user_email']
    ['enrollment-term', 'course-type', 'login-filter', 'refresh-data'].each do |key|
      session[key] = params[key]
    end

    Resque.enqueue(OnlineStudentsWorker, params)

    flash[:message] = "Report is being generated and will be emailed to you once complete."
    redirect to ('/')
  end
end
