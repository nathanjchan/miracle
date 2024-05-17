import psycopg2
import os

def connect_to_db():
    return psycopg2.connect(
        dbname=os.getenv('DATABASE_NAME'),
        user=os.getenv('DATABASE_USER'),
        password=os.getenv('DATABASE_PASSWORD'),
        host=os.getenv('DATABASE_HOST'),
        port=os.getenv('DATABASE_PORT')
    )

def do_query(conn, query):
    with conn.cursor() as cur:
        cur.execute(query)
        conn.commit()