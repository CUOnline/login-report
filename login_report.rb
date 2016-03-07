require 'wolf'

class LoginReport < Wolf::Base
  set :root, File.dirname(__FILE__)
  set :enrollment_terms, get_enrollment_terms
  self.setup

  get '/' do
    slim :index
  end

  post '/generate' do
    params['user_email'] = session['user_email']
    ['enrollment-term', 'course-type', 'login-filter', 'refresh-data'].each do |key|
      session[key] = params[key]
    end

    Resque.enqueue(LoginReportWorker, params)

    flash[:message] = "Report is being generated and will be emailed to you once complete."
    redirect to ('/')
  end
end
