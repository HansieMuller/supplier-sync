threads 3, 3
bind "tcp://127.0.0.1:#{ENV.fetch('PORT', 3000)}"
plugin :tmp_restart
