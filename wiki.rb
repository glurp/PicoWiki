#!/usr/bin/env ruby
# LGPL V2.1 () Regis d'Aubarede

###########################################################################################
#  wiki.rb 
###########################################################################################
require 'sinatra'
require 'sinatra-websocket' rescue nil
require 'redcarpet' 
require 'tmpdir'
require 'diffy'

def root() "wiki" end


        
def diff(old,neww)  [old,neww].inspect       end
def diff_css()      Diffy::CSS              end
def rpatch(d)       eval(d)[0]              end
def diff_to_html(o,n) Diffy::Diff.new(n,o).to_s(:html)  end

set :server, 'thin'  
set :sockets, []
set :root,root()
set :public_folder, root()
set :bind, '0.0.0.0'
set :port, ARGV[0] || 9191


#########################################################
##  Utilities
#########################################################
def memoized(filename,traitment)
  if File.exists?(filename)
     File.read(filename)
  else
     content=traitment.call
     File.write(filename,content)
     content
  end
end
def sjoin(pre,a,join,post) 
  "#{pre}#{(a||yield).join(join)}#{post}" 
end
def table2html(titles,content)
  h= titles ? sjoin("<tr><th>",titles,"</th><th>","</th></tr>") : ""
  b= sjoin("<tr>",nil,"</tr><tr>","</tr>") { content.map { |l| l ? sjoin("<td>",l,"</td><td>","</td>") : "" } }
  "<table class='grid'>#{h}#{b}</table>"
end

#########################################################
##   wiki actions traitments
#########################################################

def refpage(t)  t.scan(/\[(\w+)\](?!\()/).map { |pn| pn.first } end
def href(name) "<a href='/page/#{name}'>#{name}</a>" end

def page_user?(name)  name!="" && name!="index" &&  name !="templates" end
def page_exist?(name) File.exists?(page_fname(name)) end

def  page_make_view(name,md=nil)
 if name=="templates" 
   md="not viewable!"
 end
 md=wiki_render( File.read(page_fname(name)) ) unless md
 md=resolve_page_href(name,md)
 $template.gsub("%NAME%",name).gsub("%%%",md)
end

def page_make_edit(name)
  content=File.read(page_fname(name)).gsub(">","&gt;").gsub("<","&lt;")  
  $edit.gsub("%NAME%",name).gsub("%%%",content)
end

def page_stock(name,diff,content)
 content.gsub!("\r\n","\n")
 page_creation_on_content(name,content)
 filename=page_fname(name)
 fdiff=page_fdiff(name)
 File.open(fdiff,"a+") { |f| f.puts("%%% #{Time.now}") ; f.puts(diff) }
 File.open(filename,"w") { |f| f.print(content) }
 history('update',name)
end

def page_history(name)
 fdiff=page_fdiff(name)
 logs=File.read(fdiff).split(/\r?\n/).select { |line| line=~/^%%% .*$/}.map {|l| 
   date=l.gsub("%%%","").strip
   "<a href='/modif/#{name}/#{date}'>#{date}</a>"
 }
 page_make_view(name,"<h3>History of modification on '#{name}'</h3><br><br>#{logs.join("<br/>")}<br>")
end

def page_creation_on_content(name,content)
  refpage(content).select { |pn| ! File.exists?(page_fname(pn)) }.each do |pn| 
    page_create(pn)
  end
end

def resolve_page_href(nm,t) # make some transformatioàn which are not  pure markdown
  ret=t
  refpage(t).select { |pn| File.exists?(page_fname(pn)) }.each do |pn| 
    ret.gsub!("[#{pn}]",href(pn))
  end
  ret.gsub!(/I:(http|https)([^\s<]*)/,'<img src="\1\2"/>')
  ret.gsub!(/I:([^\s<]*)/) do |m| 
    name=$1.gsub("/","").gsub("..","")
    src="/assets/#{name}"
    file="#{root()}#{src}"
    if File.exists?(file)
      lien='<img src="/assets/$1"/>'.gsub('$1',name)
    else 
      lien=<<-EEND
        <div class="dform"><form method="post" action="/upload" enctype='multipart/form-data'> 
          <input type="hidden" name="MAX_FILE_SIZE" value="10000000" />
          <input type="hidden" name="page_name" value="#{nm}" />
          <input type='file' name='myfile' value='#{name}'> 
          <input type='submit' value='Upload image #{name}!'>
        </form></div>
      EEND
    end
    lien
  end
  ret
end

def  page_delete(name) 
 raise "error" unless page_user?(name)
 fname=page_fname(name)
 if File.exists?(fname)
   history "delete",name,result: "?"
   File.delete(fname)
   File.delete(page_fdiff(name))   
   history "delete",name,result: "done"
 end
end
def  page_rename(oldname,newname)
 raise "error" unless page_user?(newname)
 raise "error: page '#{newname}' already exist" if page_exist?(newname)
 fname=page_fname(oldname)
 nn=page_fname(newname)
 if  File.exists?(fname) && (! File.exists?(nn)) && oldname!=newname 
   File.rename(fname,nn)
   File.rename(page_fdiff(oldname),page_fdiff(newname))
   history "rename",oldname,result: "rename #{newname} done."
 end
end

def page_make_show_modif(name,date)
 if File.read(page_fdiff(name)) =~ /^%%%\s+#{date.gsub('+',".")}.*?^(.*?)(^%%%|$)/m
    o,n=*eval($1)
    doc='Legende:<br><div class="bc diff"><li class="del"><del>ligne detruite/modifée</del></li>
    <li class="ins"><ins>nouvelle ligne</ins></li>
    <li class="unchanged"><span>ligne inchangée</span></li></div>'
    html="<style>#{diff_css()}</style>#{doc}<hr>#{diff_to_html(o,n)}"
 else
   html= "nomatch"
 end
 page_make_view(name,"<h3>Modifications on '#{name}' at #{date}</h3><br><br>#{html}<br>")
end


############################## Generalities ##############################

def raz_cache()
 File.delete(indirwiki("list.html")) if File.exists?(indirwiki("list.html"))
 File.delete(indirwiki("summary.html")) if File.exists?(indirwiki("summary.html"))
end

def page_find_orphean()
  h=Hash.new {|h,k| h[k]=[]}
  Dir["#{File.dirname(page_fnamenv("s"))}/*"].each { |fn|
    next if fn =~/\.diff$/
    refpage(File.read(fn)).each { |r| h[r] << fn.split('/').last}
  }
  l=Dir["#{File.dirname(page_fnamenv("s"))}/*.diff"].map { |fn|
    fname=fn.split(".")[0..-2].join(".")
    name= File.basename(fname)
    if h[name]
       h.delete(name)
       next(nil)
    end
    size=File.size(fname)
    mtime=File.mtime(fname).to_s
    [name,size,mtime]
  }.compact
  
  ld=h.map {|(n,l)| [
    n,
    l.map {|r|  href(r)}.join(", ")
  ]}
  
  "<h2>Page with no caller</h2>"+
  table2html(%w{Name  Size Date},l)+
  "<br><h2>Page called but not exist</h2>"+
  table2html(%w{Name  referenced-in},ld)
end

def page_list() memoized(indirwiki("list.html"), proc {page_list1()}) end
def page_list1()
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
    [href(name),h[name].map {|r| href(r)}.join(","),size,mtime]
  }
  table2html(%w{Name References Size Date},l)
end

def page_make_summary()  memoized(indirwiki("summary.html"),proc {page_make_summary1()}) end
def page_make_summary1()
  fils=Hash.new { |h,pere| h[pere]=[]}
  pere=Hash.new { |h,fils| h[fils]=[]}
  l=Dir["#{File.dirname(page_fnamenv("s"))}/*"].map { |fn|
    next if fn =~/\.diff$/
    refpage(File.read(fn)).each { |r| 
      fils[r] << File.basename(fn)
      pere[File.basename(fn)] << r
    }
  }
  
  hdone={}
  frm=proc { |parent,s| 
     hdone[parent]=true
     s << "<ul>#{href(parent)}<br>\n"
     pere[parent].each { |f| frm.call(f,s) if ! hdone[f]}
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

post "/upload" do 
  src=params['myfile'][:tempfile]
  dst="#{root}/assets/" + params['myfile'][:filename]
  if File.size(src)<(10*1024*1024)
    File.open(dst, "wb") { |f| f.write(src.read) }
    if page_exist?(params['page_name'])
      redirect("/page/#{params['page_name']}")
    else
      return "image uploaded !"
    end
  else
    return "Sorry, the file is to big for an upload! (max: 10MB)"
  end
end

def history(event,pn,opt={})  
  File.open(flog(),"a+") { |f| 
     f.puts("#{Time.now} | #{pn} : #{event} #{opt.size>0 ? opt.inspect : ''}")
  }
  raz_cache()
end
def history_get(size=10_000)  
 logs=File.read(flog()).split(/\r?\n/)
 page_make_view("","<h3>History</h3><br><br>#{logs.join("<br/>")}<br>")
end
def make_sentry(n,regexp,line) 
  "<br><div class='searchheader'>#{href(n)}</div><ul><div class='scontent'>#{line.gsub(regexp,'<b>\1</b>')}</div></ul>"
end

def search(words) 
  rsearch= /^(.*?)(#{words.split(/\s+/).join('|')})(.*?)^/im
  rbold= /(#{words.split(/\s+/).join('|')})/i
  ret=[]
  Dir.glob(root()+"/data/*.diff").each { |fn|
     f= fn.split(".")[0..-2].join(".")
     File.read(f).gsub( rsearch ) { |l1,l2,l3|
        ret << make_sentry(File.basename(f),rbold,"#{l1}#{l2}#{l3}")
     }
     break if ret.size>100
  }
  page_make_view("","<h3>Search</h3><br><br>#{ret.join("<br/>")}<br>")
end
def plan
  fils=Hash.new { |h,pere| h[pere]=[]}
  pere=Hash.new { |h,fils| h[fils]=[]}
  l=Dir["#{File.dirname(page_fnamenv("s"))}/*"].map { |fn|
    next if fn =~/\.diff$/
    refpage(File.read(fn)).each { |r| 
      fils[r] << File.basename(fn)
      pere[File.basename(fn)] << r
    }
  }
  
  hdone={}
  frm=proc { |level,parent,s| 
     hdone[parent]=true
     s << [level,parent]
     pere[parent].each_with_index { |f,i| frm.call("#{level}.#{i+1}",f,s) if ! hdone[f]}
  }
  ["index"].each_with_object([]) { |p,la| frm.call("",p,la) }
end
def page_export
 plan.map { |(level,name)|
   content=wiki_render(File.read(page_fname(name)).gsub(">","&gt;").gsub("<","&lt;")).gsub(/<(\/)?h1>/,'<\1h2>')
   "<h1 class='hdoc'>#{level} #{name}</h1>\n#{content}"
 }.join("<br>")
end
#########################################################
#         web
#########################################################

$renderer = Redcarpet::Render::HTML.new(autolink: true,no_links: false, hard_wrap: false)
$markdown = Redcarpet::Markdown.new($renderer, extensions = {})

def wiki_render(txt)   $markdown.render( txt )                                end
def verifpn(name)      raise "name page error : '#{name}'" if name !~ /^\w*$/ end
def page_fname(name)   verifpn(name); "#{root}/data/#{name}"                  end
def page_fnamenv(name) "#{root}/data/#{name}"                                 end
def page_fdiff(name)   verifpn(name); "#{root}/data/#{name}.diff"             end
def flog()             "#{root}/event.log"                                    end
def indirwiki(f)       "#{root}/#{f}"                                         end
 
def load_templates()
  $tpl_file = File.exists?(page_fnamenv("templates")) ? page_fnamenv("templates") : __FILE__
  $tpl_mtime=File.mtime($tpl_file)
  $index,$template,$edit,$help,$css,_=File.read($tpl_file).split(/^@@ \w+\s*$/)[1..-1]
end
def load_templates_if()
  tpl_file = File.exists?(page_fnamenv("templates")) ? page_fnamenv("templates") : __FILE__
  tpl_mtime=File.mtime(tpl_file)
  load_templates() if tpl_file != $tpl_file || tpl_mtime != $tpl_mtime
end 

################# Create and verify integrity at startup wiki server ########

Dir.mkdir("#{root}") unless Dir.exists?("#{root}")
Dir.mkdir("#{root}/data") unless Dir.exists?("#{root}/data")
Dir.mkdir("#{root}/assets") unless Dir.exists?("#{root}/assets")
Dir.glob("#{root}/data/*").each do |f| 
  if f=~/.*\.diff$/
     fd=f.split(".")[0..-2].join(".")
     File.delete(f) unless File.exists?(fd)
     next
  end
  next if Dir.exists?(f)
  fd=f+".diff"
  File.write(fd,"") unless File.exists?(fd)  
end


unless File.exists?(page_fname('index'))
   page_stock("index","<creation>",$index)
end
unless File.exists?(flog())
   File.write(flog(),"creation")
end

##################### Web request on a page ##################

before  do load_templates_if()    end
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
get '/rename/:name/:newname' do  page_rename(params['name'],params['newname'])end
get '/history/:name' do   page_history(params['name']) end

post '/write/:name' do
 filename=page_fname(params['name'])
 fnew=params['data']
 $markdown.render( fnew ) # raise execption if wiki error
 fold=File.read(filename)
 page_stock(params['name'],diff(fnew,fold),fnew)
 redirect "/page/#{params['name']}"
end

get '/modif/:name/:date' do  
  page_make_show_modif(params['name'],params['date']) 
end

############### general request (not page-related)

get '/logs' do
  history_get()
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
get '/search/:words' do  search(params['words']) end

get '/help' do
 $help
end

get '/admin/:cat' do
 cat=params['cat']
 title="Admin"
 case cat
  when "menu"
    l=%w{export backup}
    c="<ul>"+l.map {|a| "<li><a href='/admin/#{a}'>#{a}</a></li>"}.join("\n")+"</ul>"
    page_make_view(title,"<h1>Administration</h1><br><br>#{c}<br>")
  when "export"
    page_make_view("",page_export)
  when "backup"
    name="wiki_backup_#{Time.now.strftime('%Y_%m_%d')}.tgz"
    system("tar","czf",name,root())
    s=File.size(name)
    page_make_view(title,"<h1>Administration</h1><br><br><a href='/#{name}'>downoad #{s/1024} Kb...</a><br><br><br>")
 end
  
end

get '/css' do 
  content_type :css
  fn=page_fname("css")
  File.exists?(fn) ? File.read(fn) : $css 
end

################ TODO

get '/push' do
  request.websocket do |ws|
    ws.onopen do
      #warn("ws connected")
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
      #warn("websocket closed")
      settings.sockets.delete(ws)
    end
  end
end
raz_cache()


__END__
@@ index
=== Hello

This is primary page for your own Wiki
you can edit it by click on 'edit' in footer of this pages.

For create a new page, write a tag like [name_new_page] in a edited page. this page(s)
will be created, empty ...

image: I:tc.png

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
    <div id='title'>
      %NAME%
      <div class='search'>
         search :
         <input type='text' id='search' value=''>
         <input type='button' value=' go ' onclick="location.href='/search/'+document.getElementById('search').value">
      </div>
    </div>
    <div id="container">
%%%
    </div>
    <div id='preview'></div>
    <div id='footer'>
      <a href='/edit/%NAME%'>Edit</a> |
      <a href='/help'>Help</a> |
      <a href='/history/%NAME%'>Page history</a> | |
      <a href='/summary'>Summary</a> |
      <a href='/orphean'>Integrity check</a> |
      <a href='/list'>Page list</a> |
      <a href='/logs'>History</a> |
      <a href='/admin/menu'>admin</a> |
      <a href='/page/index'> Home </a>
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
    <script>
    function newname(elem) {
       var n=prompt("new name for page %NAME ?");
       if (n && n.length>0) {
          console.log(elem.attributes.href.value)
          elem.attributes.href.value=elem.attributes.href.value.replace(/%:%/,n);
          console.log(elem.attributes.href.value)
          return false;
       }
       return true;
    }
    </script>
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
      <a href='/rename/%NAME%/%:%' onclick='newname(this)'>Rename</a> |
      <a href='/help'>Help</a> |
      <a href='/page/index'>Home</a> 
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
  <tr><td>```aa```</td><td><b><code>aa</code></b></td><td>code</td></tr>
  <tr><td>I:tc.png</td><td><b><img src="/assets/tc.png"></b></td><td>image, dans /assets</td></tr>
  <tr><td>!(http://localhost/assets/tc.png)</td><td><b><img src="/assets/tc.png"></b></td><td>image</td></tr>
  <tr><td>Enumeration : <br>* choix 1<br>* choix 2</td><td>Enumeration<ul><li>choix 1</li><li>choix 2</li></ul></td><td>liste a puces</td></tr>
  <tr><td>Enumeration numérotée : <br>1 choix 1<br>1 choix 2</td><td>Enumeration<ol><li>choix 1</li><li>choix 2</li></ol></td><td>liste numerotée</td></tr>
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

h1   { background: #006666; color: white ; text-align: center;padding: 10px 0px 10px 0px;}
h1.hdoc { background: #FFF; color: #000; text-align: left; padding: 10px 0px 10px 0px; border-bottom: 2px solid black;}
div#title   {  color: #EE8833 ; text-align: left; font-size: 30px; margin-left: 20px}

div#footer   {  margin-left: 10px; border-top: 2px solid black; padding-top: 10px;text-align: center;}

div#container   {   margin-left: 30px}

div#footer a { font-weight: bold; ; color: #B73;}

table.grid { border: 2px solid #044 ; border-collapse: collapse ; width:90%}

table.grid th { border: 2px solid #AAA ; background: #FFA;}

table.grid td { border: 2px solid #AAA ; margin: 3px 10px 3px 10px;}

div.bc { margin: 10px 100px 10px 100px; background: #FFA; border: 2px solid black;width:300px;}

div.search {  position:absolute; text-align:right; right:10px; top:0px;}

div.searchheader { font-weight: bold; color: #46F;}
div.scontent     { width:70%;}

