require 'bundler/setup'
require 'wolf_core'
require 'wolf_core/auth'
require './online_students_worker'

class OnlineStudentsApp < WolfCore::App
  set :root, File.dirname(__FILE__)
  set :views, ["#{root}/views", settings.base_views]

  set :title, 'Online Enrollment Report'

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
