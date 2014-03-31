PicoWiki
--------

PicoWiki : 

* All code, html templates, css , are in the one-file application
* No database : data are in the file system, history are append in texts files
* CSS, templates and index file can be editable in the wiki
* no installation ! : ruby and a filesystem is good enough...


Features

* Page: view, edit, link internal/external, rename, delete pages, search
* automatic summary (reflexion on pages contents and directories contents)
* integrity check:  list of orphean pages, list of dead link pages, check at server startup
* Images upload, list, delete
* Admin: export (to one html file)
* Admin: backup (download dated tgz)

Inspired by tipiwiki.

Todo
----
* verify with a big wiki : wikified a bible?
* authentification (?)
* Websocket (work but not use..) : to make wiki pages dynamics...
* mini file-explorer : every user could upload/consult/download some files


Usage
-----
    > gem install sinatra redcarpet 
    > gem install diffy sinatra-websocket  # optionaly !!!
    > cd ...wiki-root
    > ruby /path-to-source/wiki.rb [tcp-port]


Wiki data are in the current directory (wikiroot in the example)
See wiki.rb header for some tuning.

License
-------
LGPL
