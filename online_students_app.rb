require 'bundler/setup'
require 'wolf_core'

require_relative './online_students_worker'

class OnlineStudentsApp < WolfCore::App
  set :title, 'Online Enrollment Report'
  set :root, File.dirname(__FILE__)
  set :auth_paths, [/.*/]

  get '/' do
    slim :index
  end

  post '/' do
    params['user_email'] = session['user_email']
    ['enrollment-term', 'course-type', 'login-filter', 'refresh-data'].each do |key|
      session[key] = params[key]
    end

    Resque.enqueue(OnlineStudentsWorker, params)

    flash[:success] = "Report is being generated and will be emailed to you once complete."
    redirect to ('/')
  end
end
