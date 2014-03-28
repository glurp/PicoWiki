PicoWiki
--------

PicoWiki : 

* All code, html template, basic css , are in the one-file application
* No database : data are in the file system, history are append in texts files
* CSS and index file can be editable in the wiki
* no installation ! : ruby and a filesystem is good enough...


Features

* view, edit, link, rename, delete pages
* automatic summary (reflexion on pages contents and directories contents)
* list of orphean pages

Inspired by tipiwiki (php).

Todo
----

* images upload,...
* authentification (?)
* Websocket not ready : the idea is to append a real-time notification to all client connected
* mini file explorer, dropbox like : every user can upload/consult/download some files


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
