# utilities for cgi programs

import sys, os, base64, psycopg2, cgi, string

# subclass cgi.FieldStorage, force getvalue text to legal ascii
class submitted(cgi.FieldStorage):
    def getvalue(self, key, default=None):
        v=cgi.FieldStorage.getvalue(self, key, default)
        if isinstance(v,str): v=filter(lambda c: c in string.printable, v).strip()
        return v

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
    return s

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
    return ("<form style='float:left' method=get "+(action or "")+">"+
            "<button class=click type=submit></button>"+
            "".join("<input type=hidden name='%s' value='%s'>" % escape((n,v)) for n,v in params.items())+
            "</form>"+
            "&nbsp;"+escape(label))

# footer shows home button, current server time and elapsed time
def tick_footer():
    conn=psycopg2.connect('dbname=factory')
    cur=conn.cursor()
    cur.execute("select uct()")
    now=cur.fetchone()
    return """
        <hr>
        <div class=footer>
            <span>Retrieved """ + now[0].strftime("%Y-%m-%d %H:%M:%S") + """ UCT&nbsp;</span>
            <span id=ticks></span>
        </div>
        <script>
        let start=new Date;
        function tick()
        {
            let diff=Math.floor((new Date - start)/1000);
            var t='';
            if (diff >= 86400)
            {
                var d = Math.floor(diff / 86400);
                t+=d+((d==1)?' day,':' days, ');
            }
            if (diff >= 3600)
            {
                var h =Math.floor((diff/ 3600) % 24);
                t+=h+((h==1)?' hour,':' hours, ');
            }
            if (diff >= 60)
            {
                var m=Math.floor((diff / 60) % 60);
                t+=m+((m==1)?' minute, ':' minutes, ');
            }
            var s=Math.floor(diff % 60);
            t+=s+((s==1)?' second':' seconds');
            document.getElementById('ticks').innerHTML = "("+t+" ago)"
        }
        ticker=setInterval(tick,1000);
        </script>
    """

# Return a span containg label and help text (appears on hover)
def help(label, text):
    return """<span class=help title="%s">%s</span>""" % (text.strip().replace('"','&quot;'),label.strip())

# Given a title, optional styles, and html content, return
# an html page with cache controls, title, footer, etc.
def html(title, style, content):
    headers = ["Content-type: text/html; charset=utf-8","Cache-Control: no-cache,max-age:120,must-revalidate"]
    s=("\n".join(headers) + "\n\n" +
    "<!DOCTYPE html>\n" +
    "<html> <head> <title>" + title + "</title></head>" +
    """<style>
        body { font-family: monospace; background-color: white; }
        input { font-family: monospace; padding: 0; }
        input[type=text] { width: 50ch; }
        input.narrow[type=text] { width: 3ch; }
        select { font-family: monospace; padding: 0; width: 100%; }
        table td { padding: 4px 1ch; font-family: monospace; }
        table.form { margin: 0; }
        table.form td { white-space: nowrap; }
        table.form td:nth-child(1) { text-align: right; font-weight: bold; }
        table.data { border-collapse: collapse; }
        table.data td { border: solid 1px black; max-width: 50ch; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        table.data tr:first-child td { font-weight: bold; position: sticky; top: 0; background-color: white; box-shadow: 0 0 0 1px black; }
        table.status { border-collapse: collapse; }
        table.status td { border: solid 1px black; }
        table.status tr:first-child td { font-weight: bold; position: sticky; top: 0; background-color: white; box-shadow: 0 0 0 1px black; }
        .PASSED { background-color: lightgreen; color: black; font-weight: bold }
        .FAILED { background-color: #D00000; color: white; font-weight: bold; }
        .FAILING { background-color: purple; color: white; font-weight: bold; }
        .COMPLETE { background-color: green; color: white; font-weight: bold; }
        .TESTING { background-color: blue; color: white; }
        .UNKNOWN { background-color: grey; color: black; }
        .STALE { background-color: yellow; color: black; font-weight: bold; }
        button { padding: 1px; }
        button.click { border: 1px outset black; background-color: white; padding: 0; height: 14px; width: 14px; vertical-align: top; }
        button.click:hover { background-color: grey; }
        div.footer { float: left; padding-bottom: 10px; }
        div.footer form { float: left; }
        /* div.footer button { font-size: 8px; float: left; } */
        div.footer span { font-size: 12px; float: left; }
        span.help { cursor: help; }
        nav ul { list-style-type: none; margin: 0; padding: 0; overflow: hidden; background-color: black; }
        nav li { float: left; border-right: 1px solid white; }
        nav li:last-child { float: right; border-right: none; border-left: 1px solid white; }
        nav li a { display: block; color: white; text-align: center; padding: 4px 16px; text-decoration: none; }
        nav li a:hover { background-color: grey }
    """ + (style or "") +
    """ </style> <body> <nav> <ul>
    <li><a href="/cgi-bin/status">Current Status</a></li>
    <li><a href="/cgi-bin/devices">Device History</a></li>
    <li><a href="/cgi-bin/sessions">Session History</a></li>
    <li><a href="/cgi-bin/tests">Test History</a></li>
    <li><a href="/cgi-bin/provisioned">Provisioned Data</a></li>
    <li><a href="/cgi-bin/stations">Station Manager</a></li>
    <li><a href="/cgi-bin/builds">Build Manager</a></li>
    <li><a href="/index.html">Home</a></li>
    </ul> </nav> <h2>""" + title + "</h2>" + content + "</body> </html>")
    return "\n".join(" ".join(l.split()) for l in s.strip().splitlines())

def plaintext(content):
    return "Content-type: text/plain; charset=utf-8\n\n" + content

# Authenticate user, realm appears in the browser password dialog, user is
# specified as "name:password". If not authenticated then aborts with status
# 401, so must be called before any other output.
# Note apache2 must be configured with "CGIPassAuth on"
def authenticate(realm, user):
    if not "GATEWAY_INTERFACE" in os.environ: return # skip if cgi is run from command line
    if "HTTP_AUTHORIZATION" in os.environ:
        auth = base64.decodestring(os.environ["HTTP_AUTHORIZATION"].split()[1])
        if auth == user: return
    print 'Content-type: text/plain\nStatus: 401 Unauthorized\nWWW-Authenticate: basic realm="%s"\n' % realm
    sys.exit(0)

# Issue a redirect to the current page and exit
def reload():
    print 'Content-type: text/plain\nStatus: 302 Found\nLocation:',os.getenv('SCRIPT_NAME'),'\n'
    sys.exit(0)
