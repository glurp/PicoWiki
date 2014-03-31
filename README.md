PicoWiki
--------

PicoWiki : 

* All code, html template, basic css , are in the one-file application
* No database : data are in the file system, history are append in texts files
* CSS and index file can be editable in the wiki
* no installation ! : ruby and a filesystem is good enough...


Features

* view, edit, link internal/external, rename, delete pages, search
* images upload, list, delete
* admin: export (to one html file), backup (download dated tgz)
* automatic summary (reflexion on pages contents and directories contents)
* integrity check:  list of orphean pages, list of dead link pages, check at server startup

Inspired by tipiwiki (php).

Todo
----

* authentification (?)
* Websocket (work but not use..) : to make wiki pages dynamics...
* mini file explorer, dropbox like : every user could upload/consult/download some files


Usage
-----
    > gem install sinatra redcarpet diffy sinatra-websocket
    > cd ...wiki-root
    > ruby /path-to-source/wiki.rb [tcp-port]


Wiki data are in the current directory (wikiroot in the example)
See wiki.rb header for some tuning.

License
-------
LGPL
