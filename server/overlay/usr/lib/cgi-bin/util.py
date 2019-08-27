# utilities for cgi programs

import sys, os, base64, psycopg2

# return string, list, or tuple with html meta-characters escaped
def escape(ss, align=False):
    if isinstance(ss, list): return list(escape(s) for s in ss)
    if isinstance(ss, tuple): return tuple(escape(s) for s in ss)
    if ss is None: ss=''
    return reduce(lambda s,t: s.replace(t[0],"%s"%t[1]),[str("" if ss is None else ss), ('&','&amp;'), ('<','&lt;'), ('>','&gt;'), ('"','&quot;'), ('\'','&#39;'), ('%','&#37;'), ('\n','<br>'), (' ','&nbsp;') if align else ('','')])

# generate html select structure
# 'name' is the name of the field, 'options' is a dict of {option value:display name}, 'selected' is the option value to select by default (or None)
def select(name, options, selected):
    s="<select name='%s'>" % name
    for o in options:
        s += "<option value='%s' %s>%s</option>" % (escape(o), "selected" if o == selected else "", escape(options[o]))
    s += "</select>"
    return s;

# generate html table structure
# rows is a list, or a tuple pf (table_class, rows)
# each row is a list, or a tuple of (tr_class, row)
# each row element is a str, or a tuple of (td_class, str)
def table(rows):
    if isinstance(rows,tuple):
        s = "<table class='%s'>" % rows[0] if rows[0] else "<table>"
        rows=rows[1]
    else:
        s = "<table>"
    for row in rows:
        if isinstance(row,tuple):
            s += "<tr class='%s'>" % row[0] if row[0] else "<tr>"
            row=row[1]
        else:
            s += "<tr>"
        for r in row:
            if isinstance(r,tuple):
                s += "<td class='%s'>%s</td>" % r if r[0] else "<td>%s</td>" % r[1]
            else:
                s += "<td>%s</td>" % r
        s += "</tr>"
    s += "</table>"
    return s

# generate clickable button
def click(label, action, params):
    return ("<form method=get "+(action or "")+">"+
            "<button class=click type=submit></button>"+
            "".join("<input type=hidden name='%s' value='%s'>" % escape((n,v)) for n,v in params.items())+
            "&nbsp;"+escape(label)+
            "</form>")

# global styles
gstyles="""
    table td { padding-right: 10px; padding-left: 10px; padding-top: 4px; padding-bottom: 4px; font-family:monospace; vertical-align:top }
    
    table.form { margin: 20px }
    table.form td:nth-child(1) { text-align: right; font-weight: bold; }

    table.data { border-collapse: collapse; }
    table.data td { border: solid 1px; }
    table.data tr:nth-child(1) { font-weight: bold; }
    
    table tr.pass, table td.pass { background-color: green; color: white; font-weight: bold }
    table tr.pass a, table td.pass a { color: white }

    table tr.fail, table td.fail { background-color: #D00000; color: white; font-weight: bold }
    table tr.fail a, table td.fail a { color: white }

    button.click { border: 1px outset darkgrey; background-color: white; padding: 0; height:12px; width:12px; border-radius:12px; vertical-align: super }
    button.click:hover { background-color: grey; }

    div.footer { float:left; } 
    div.footer form { float: left; }
    div.footer button { font-size: 8px; float:left; }
    div.footer span { font-size: 12px; float:left; }

    input { font-family:monospace }
"""    

# Given html title, additional styles, and content, return html page with cache controls, title, footer, etc
def html(title, style, content):
    conn=psycopg2.connect('dbname=factory')
    cur=conn.cursor()
    cur.execute("select uct()")
    now=cur.fetchone();

    headers = ["Content-type: text/html; charset=utf-8","Cache-Control: no-cache,max-age:120,must-revalidate"]
    s=("\n".join(headers) + "\n\n" + 
       """
       <!DOCTYPE html>
       <html> <head>
       <title>""" +  title + """</title>
       <style>""" + gstyles + (style or "") + """</style>
       <script>
       let start=new Date; 
       function tick() 
       {
           let diff=Math.floor((new Date - start)/1000);
           t=''; 
           if (diff > 86400) 
           {
               d = Math.floor(diff / 86400);
               t+=d+((d==1)?' day,':' days, ');
           } 
           if (diff > 3600)
           {
               h =Math.floor((diff/ 3600) % 24);
               t+=h+((h==1)?' hour,':' hours, ');
           }
           if (diff > 60)
           {
               m=Math.floor((diff / 60) % 60);
               t+=m+((m==1)?' minute, ':' minutes, ');
           } 
           s=Math.floor(diff % 60);
           t+=s+((s==1)?' second':' seconds');
            
           document.getElementById('ago').innerHTML = "("+t+" ago)"
       }       
      
       ticker=setInterval(tick,1000);  
       </script>
       </head> <body> 
       <h2>""" + title + """</h2>       
       """ + content + """
       <hr>
       <div class=footer>
          <form action='/'><button>Home</button></form>
          <span>&nbsp; Server time is """ + now[0].strftime("%Y-%m-%d %H:%M:%S") + """ UCT &nbsp;</span> 
          <span id=ago></span>
       </div> 
       </body> 
       </html>""")
    return '\n'.join(map (lambda x:' '.join(x.split()),map(lambda x:x.strip(),s.split('\n'))))

def plaintext(content):
    return "Content-type: text/plain; charset=utf-8\n\n" + content

# Authenticate user, realm appears in the browser password dialog, user is
# specified as "name:password". If not authenticated then aborts with status
# 401, so must be called before any other output.
def authenticate(realm, user):
    if not "GATEWAY_INTERFACE" in os.environ: return # skip if run from command line
    auth=""
    try:
        auth = base64.decodestring(os.environ["HTTP_AUTHORIZATION"].split()[1])
        if auth != user:
            raise Exception
    except:
        print 'Content-type: text/plain\nOOPS: %s\nStatus: 401 Unauthorized\nWWW-Authenticate: basic realm="%s"\n' % (auth,realm)
        sys.exit(0)
