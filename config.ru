require './online_students_app'
require './online_students_worker'

map ('/auth') { run WolfCore::Auth }
map ('/')     { run OnlineStudentsApp }
