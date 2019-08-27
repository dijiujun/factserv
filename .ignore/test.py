#!/usr/bin/python2

import psycopg2, psycopg2.extras, json, datetime

class unstamp(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, date):
            return str(obj)
        return json.JSONEncoder.default(self, obj)

conn=psycopg2.connect('dbname=test')
cur=conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
cur.execute("select * from test")
rows=cur.fetchall()

for r in rows:
    for k in r.keys():
        if isinstance(r[k], datetime.datetime):
            r[k] = str(r[k])
        elif not isinstance(r[k], (int,str)):
            r[k] = str(r[k])

print json.dumps(rows)            

