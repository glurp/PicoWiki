#!/usr/bin/env ruby
###########################################################################################
#  wiki.rb : wiki dynamique : wiki+ tous les connect� 
#            sont averites en temps reel des nouveaut�es
###########################################################################################
require 'sinatra'
require 'sinatra-websocket'
require 'redcarpet' 

require 'diff/lcs'
def diff(s1,s2) Diff::LCS.LCS(s1, s2) end
def patch(s1,diff) Diff::LCS.patch!(seq1, diffs) end

set :server, 'thin'  
set :sockets, []
set :root,File.dirname(__FILE__)
set :public_folder, File.dirname(__FILE__)
set :bind, '0.0.0.0'
set :port, ARGV[0] || 9191


#########################################################
##
#########################################################

def refpage(t) 
 t.scan(/\[(\w+)\](?!\()/).map { |pn| pn.first }
end

def  page_make_view(name,md=nil)
 md=wiki_render( File.read(page_fname(name)) ) unless md
 md=resolve(md)
 $template.gsub("%NAME%",name).gsub("%%%",md)
end
def page_make_edit(name)
  content=File.read(page_fname(name))
  $edit.gsub("%NAME%",name).gsub("%%%",content)
end

def page_stock(name,diff,content)
 page_creation(name,content)
 filename=page_fname(name)
 fdiff=page_fdiff(name)
 File.open(fdiff,"a+") { |f| f.puts("%%% #{Time.now}") ; f.puts(diff) }
 File.open(filename,"w") { |f| f.print(content) }
 history('update',name)
end

def page_history(name)
 fdiff=page_fdiff(name)
 logs=File.read(fdiff).split(/\r?\n/).select { |line| line=~/^%%% .*$/}
 page_make_view(name,"<h3>History of modification on '#{name}'</h3><br><br>#{logs.join("<br/>")}<br>")
end

def page_creation(name,content)
  refpage(content).select { |pn| ! File.exists?(page_fname(pn)) }.each do |pn| 
    page_create(pn)
  end
end

def resolve(t)
  ret=t
  refpage(t).select { |pn| File.exists?(page_fname(pn)) }.each do |pn| 
    t.gsub!("[#{pn}]","<a href='/page/#{pn}'>[#{pn}]</a>")
  end
  ret
end

def  page_delete(name) 
 raise "error" unless page_move_ok?(name)
 fname=page_fname(name)
 if File.exists?(fname)
   history "delete",name,result: "?"
   File.delete(fname)
   File.delete(page_fdiff(name))   
   history "delete",name,result: "done"
 end
end
def  page_rename(oldname,newname)
 raise "error" unless page_move_ok?(name)
 raise "error" unless page_move_ok?(newname)
 fname=page_fname(name)
 nn=page_fname(newname)
 if  File.exists?(fname) && (! File.exists?(nn)) && oldame!=newname 
   history "rename",name,result: "?"
   File.write(nn,File.read(fname))
   File.write(page_fdiff(newname),page_fdiff(name))   
   history "rename",name,result: "creation #{newname} done."
   File.delete(page_fdiff(name))   
   File.delete(fname)   
   history "rename",name,result: "delete #{name} done."
 end
end

def page_move_ok?(name)
  name!="" && name!="index"
end

############################## Genralities ##############################

def page_find_orphean()
  h={}
  l=Dir["#{File.dirname(page_fnamenv("s"))}/*"].map { |fn|
    next if fn =~/\.diff$/
    refpage(File.read(fn)).each { |r| h[r]=true}
  }
  l=Dir["#{File.dirname(page_fnamenv("s"))}/*.diff"].map { |fn|
    fname=fn.split(".")[0..-2].join(".")
    name= File.basename(fname)
    next if h[name]
    size=File.size(fname)
    mtime=File.mtime(fname).to_s
    "<td><a href='/page/#{name}'>#{name}</a></td><td>#{size}</td><td>#{mtime}</td>"
  }.join("</tr><tr>")
  "<table class='grid'><tr><th>Name</th><th>Size</th><th>Date</th></tr><tr>#{l}</tr></table>"
end

def page_list()
  h=Hash.new { |h,k| h[k]=[]}
  l=Dir["#{File.dirname(page_fnamenv("s"))}/*"].map { |fn|
    next if fn =~/\.diff$/
    refpage(File.read(fn)).each { |r| h[r] << File.basename(fn)}
  }
  l=Dir["#{File.dirname(page_fnamenv("s"))}/*.diff"].map { |fn|
    fname=fn.split(".")[0..-2].join(".")
    name= File.basename(fname)
    size=File.size(fname)
    mtime=File.mtime(fname).to_s
    refs= h[name].join(", ")
    "<td><a href='/page/#{name}'>#{name}</a></td><td>#{refs}</td><td>#{size}</td><td>#{mtime}</td>"
  }.join("</tr><tr>")
  "<table class='grid'><tr><th>Name</th><th>References</th><th>Size</th><th>Date</th></tr><tr>#{l}</tr></table>"
end

def page_make_summary()
  fils=Hash.new { |h,pere| h[pere]=[]}
  pere=Hash.new { |h,fils| h[fils]=[]}
  l=Dir["#{File.dirname(page_fnamenv("s"))}/*"].map { |fn|
    p fn
    next if fn =~/\.diff$/
    refpage(File.read(fn)).each { |r| 
      fils[r] << File.basename(fn)
      pere[File.basename(fn)] << r
    }
  }
  
  hdone={}
  frm=proc { |parent,s| 
     hdone[parent]=true
     s << "<ul><a href='/page/#{parent}'>#{parent}</a><br>"
     g="\n"
     pere[parent].each { |f| frm.call(f,g) if ! hdone[f]}
     s << g
     s << "</ul>\n"
  }
  lroot=pere.keys.select { |k| fils[k].size==0}
  lroot.each_with_object("") { |p,html| frm.call(p,html) }
end

def page_create(name) 
 filename=page_fname(name)
 fdiff=page_fdiff(name)
 File.open(fdiff,"a+") { |f| f.puts("%%% #{Time.now}") ; f.puts("") }
 File.open(filename,"w") { |f| f.print("") }
 history('creation',name)
end

def history(event,pn,opt={})  File.open(flog(),"a+") { |f| f.puts("#{Time.now} | #{pn} : #{event} #{opt.size>0 ? opt.inspect : ''}")} end
def history_get(size=10_000)  
 logs=File.read(flog()).split(/\r?\n/)
 page_make_view("","<h3>History</h3><br><br>#{logs.join("<br/>")}<br>")
end

#########################################################
#         web
#########################################################

$renderer = Redcarpet::Render::HTML.new(autolink: true,no_links: false, hard_wrap: false)
$markdown = Redcarpet::Markdown.new($renderer, extensions = {})
def wiki_render(txt)  $markdown.render( txt ) end

$index,$template,$edit,$help,$css,_=File.read(__FILE__).split(/^@@ \w+\s*$/)[1..-1]

Dir.mkdir("wiki") unless Dir.exists?("wiki")
Dir.mkdir("wiki/data") unless Dir.exists?("wiki/data")

def verifpn(name)  raise "name page error : '#{name}'" if name !~ /^\w*$/ end
def page_fname(name) verifpn(name); "wiki/data/#{name}"      end
def page_fnamenv(name)              "wiki/data/#{name}"      end
def page_fdiff(name) verifpn(name); "wiki/data/#{name}.diff" end
def flog()           "wiki/event.log"         end

unless File.exists?(page_fname('index'))
   page_stock("index","<creation>",$index)
end

get '/' do redirect '/page/index' end

get '/page/:name' do
 filename=page_fname(params['name'])
 unless File.exists?(filename)
    page_stock(params['name'],"","")
    return
 end
 page_make_view(params['name'])
end

get '/edit/' do redirect '/page/index'  end
get '/edit/:name' do
 filename=page_fname(params['name'])
 unless File.exists?(filename)
 end
 page_make_edit(params['name'])
end

get '/delete/:name' do  page_delete(params['name']) end
get '/rename/:name' do page_rename(params['name'],params['newname'])end
get '/history/:name' do   page_history(params['name']) end
get '/logs' do            history_get()                end

post '/write/:name' do
 filename=page_fname(params['name'])
 fnew=params['data']
 $markdown.render( fnew ) # raise execption if wiki error
 fold=File.read(filename)
 page_stock(params['name'],diff(fnew,fold),fnew)
 redirect "/page/#{params['name']}"
end

get '/summary' do
   page_make_view("","<h3>Summary</h3><br><br>#{page_make_summary()}<br>")
end
get '/orphean' do
 c=page_find_orphean()
 page_make_view("","<h3>Orhean pages</h3><br><br>#{c}<br>")
end

get '/list' do
 c=page_list()
 page_make_view("","<h3>Pages</h3><br><br>#{c}<br>")
end

get '/help' do
 $help
end

get '/css' do 
  content_type :css
  fn=page_fname("css")
  File.exists?(fn) ? File.read(fn) : $css 
end


get '/push' do
  request.websocket do |ws|
    ws.onopen do
      warn("ws connected")
      settings.sockets << ws
      #EM.next_tick { ws.send($gtext.to_html) rescue p $! }
    end
    ws.onmessage do |msg|
      markdown = RedcarpetCompat.new(msg)
      $gtext=markdown
      #html = markdown.to_html
      #File.write('markdown.save.txt',markdown) 
      #EM.next_tick { settings.sockets.each{|s| s.send(html) } }
    end
    ws.onclose do
      warn("websocket closed")
      settings.sockets.delete(ws)
    end
  end
end

__END__
@@ index
=== Hello

This is primary page for your own Wiki
you can edit it by click on 'edit' in footer of this pages.

For create a new page, write a tag like [name_new_page] in a edited page. this page(s)
will be created, empty ...


@@ template
<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Wiki</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="/css">
</head>
<body>
    <div id='title'>%NAME%</div>
    <div id="container">
%%%
    </div>
    <div id='preview'></div>
    <div id='footer'>
      <a href='/edit/%NAME%'>Edit</a> |
      <a href='/help'>Help</a> |
      <a href='/history/%NAME%'>Page history</a> | |
      <a href='/summary'>Summary</a> |
      <a href='/orphean'>Orphean pages</a> |
      <a href='/list'>List all pages and references</a> |
      <a href='/logs'>History</a> |
      <a href='/page/index'>((Home))</a> |
      &copy; Regis d'Aubarede
    </div>
    <script type="text/javascript">
        var ws = null;
        function clearing() { $('textarea').text('');         }
        function sending()  { ws.send( $('textarea').val() ); }
        
        if (! WebSocket)
          alert("Your Browser is not compatible with HTML5 !")
        else {
          ws= new WebSocket('ws://' + window.location.host + '/push');
          ws.onopen = function ()      { console.log('ws:connected'); };
          ws.onclose = function (ev)   { console.log('ws:closed'); };
          ws.onmessage = function (ev) { $('#preview').html(ev.data); };
          ws.onerror = function (ev)   { console.log('ws error:'+ev); };
        }
    </script>
</body>
</html>

@@ edit
<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Wiki</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="/css">
</head>
<body>
    <div id='title'>Edit '%NAME%'</div>
    <div id="container">
      <form method="post" action="/write/%NAME%">
        <p><textarea name="data" style='width: 90%;height: 700px;'>%%%</textarea></p>
        <p><center><input type="submit" value=" publish " /></center></p>
      </form>
    </div>
    <div id='footer'>
      <a href='/delete/%NAME%'>Delete</a> |
      <a href='/rename/%NAME%'>Rename</a> |
      <a href='/help'>Help</a> |
      <a href='/page/index'>Home</a> 
      &copy; Regis d'Aubarede
    </div>
    <div id='preview'></div>
</body>
</html>
@@ help
<htm>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WikiHelp</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="/css">
</head><body>
<h1>Documentation du langage Markdown</h1>

<p>Ce wiki utilise le langage de tag <b>Markdown</b>.</p>

<p>Markdown est un langage de balisage léger créé par John Gruber et Aaron Swartz.
Son but est d'offrir une syntaxe facile à lire et à écrire. Un document formaté selon 
Markdown devrait pouvoir être publié comme tel, en texte, sans donner l’impression qu’il 
a été marqué par des balises ou des instructions de formatage. Bien que sa syntaxe a été 
influencée par plusieurs filtres de conversion de texte existants vers HTML — dont 
Setext1, atx2, Textile, reStructuredText, Grutatext3 et EtText4 —, la source d’inspiration 
principale est le format du courrier électronique en mode texte.</p>
( &copy; wikiperia )

<ul><table class='grid'>
  <tr><th>Tag</th><th>Mise en forme</th><th>Commentaire</th></tr>
  <tr><td>*aa*</td><td><i>aa</i></td><td>italic</td></tr>
  <tr><td>**aa**</td><td><b>aa</b></td><td>bold</td></tr>
  <tr><td>Enumeration : <br>* choix 1<br>* choix 2</td><td>Enumeration<ul><li>choix 1</li><li>choix 2</li></ul></td><td>bold</td></tr>
  <tr><td>Enumeration numérotée : <br>1 choix 1<br>1 choix 2</td><td>Enumeration<ol><li>choix 1</li><li>choix 2</li></ol></td><td></td></tr>
  <tr><td>aaaa<br>===</td><td><h1>aa</h1></td><td>titre</td></tr>
  <tr><td>aaaa<br>----</td><td><h2>aa</h2></td><td>titre 2</td></tr>
  <tr><td>aaaa<br>- - -</td><td><h3>aa</h3></td><td>titre 3</td></tr>
  <tr><td>[Lien]</td><td><a href='#'>Lien</a></td><td>lien sur une page interne<br> creation de la page si elle <br>existe pas</td></tr>
  <tr><td>[Search](http://google.com)</td><td><a href='#'>Search</a></td><td>lien vers une page externe</td></tr>
</table></ul>
<br>
Lien officiel: <a href='http://daringfireball.net/projects/markdown/syntax'>Doc</a>
</body>
</html>
@@ css
body { margin: 0px;}
h1   { background: black; color: white ; text-align: center;}
div#title   {  color: #EE8833 ; text-align: left; font-size: 30px; margin-left: 20px}
div#footer   {  margin-left: 10px; border-top: 2px solid black; text-align: center;}
div#container   {   margin-left: 30px}
div#footer a { font-weight: bold; ; color: #B73;}
table.grid { border: 2px solid #AAA ; border-collapse: collapse}
table.grid th { border: 1px solid #AAA ; background: #FFE;}
table.grid td { border: 1px solid #AAA ;}