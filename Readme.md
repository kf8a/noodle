Noodle
=========

A script to evaluate and post the contents of an eml harvest list

    git clone https://github.com/kf8a/noodle.git
    bundle
    ruby pasta.rb harvestlist_url

If you need to access pasta with authentication copy the credentials.yaml.example to
credentials.yaml and adjust the user name and password

To get help:

    ruby pasta.rb -h

Local caching
-------------

If the time required to get out of a database system is too large, the --cache flag can be used to
download a copy of the data into the data directory before submitting the request to PASTA. This flag
assumes that there is a webserver on the local machine that serves the data directory. One easy way to do this
is to use the caddy webserver[https://caddyserver.com/] in the root of the project 
