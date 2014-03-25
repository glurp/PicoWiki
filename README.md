PicoWiki
--------

PicoWiki : 

* All code, html template, basic css , are in the one-file application
* No database : data are in the file system, history are append in texts files
* CSS and index file can be editable in the wiki
* no installation ! : ruby and a filesystem is dood enough...


Features

* edit, rename, delete pages
* automatic summary (reflexion on pages contents and direcorys contents
* list of orphean pages

Inspired by tipiwiki (php).

Todo
----

* images upload,...
* authentification (?)
* History is not ok ; diff & patch seem not work.
* Websocket not ready : the idea is to append a real-time notification to all client connected
* mini file ewplorer, dropbox like :)


Usage
-----
    > gem install sinatra redcarpet diff-lcs
    > cd ...wiki-root
    > ruby /path-to-source/wiki.rb [tcp-port]


wiki data are in the current directory (wikiroot in the example)
See wiki.rb header for some tuning.

License
-------
LGPL
