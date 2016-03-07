require './login_report'
require './login_report_worker'

map ('/auth') { run Wolf::Auth }
map ('/')     { run LoginReport }
