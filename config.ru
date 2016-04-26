require './online_students_app'

map ('/auth') { run WolfCore::Auth }
map ('/')     { run OnlineStudentsApp }
