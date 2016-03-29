require './login_report_app'
require './login_report_worker'

map ('/auth') { run Wolf::Auth }
map ('/')     { run LoginReportApp }
