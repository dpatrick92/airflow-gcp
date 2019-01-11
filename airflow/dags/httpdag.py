from datetime import datetime
import airflow
from airflow import DAG
from airflow.operators.dummy_operator import DummyOperator
from airflow.operators.http_operator import SimpleHttpOperator
from airflow.operators.python_operator import PythonOperator
from airflow.hooks import HttpHook


import requests
import config
import json

args = {
    'start_date': airflow.utils.dates.days_ago(2),
    'provide_context': True,
}

dag = DAG('my_http_dag', schedule_interval="@once", default_args=args)

def parse(**kwargs):
    r = requests.get(config.simplyrets.hostname, auth = (config.simplyrets.username, config.simplyrets.password))
    kwargs['ti'].xcom_push(key='simplyretsreturn', value=r.text)

def puller(**kwargs):
    ti = kwargs['ti']

    # get value_1
    v1 = ti.xcom_pull(key=None, task_ids='python_parse')
    v1 = json.loads(v1)
    return v1[0]['office']

def httpcall(**kwargs):
    api_hook = HttpHook(http_conn_id='http_default', method='GET')
    resp = api_hook.run('')
    resp = json.loads(resp.text)
    print resp


to = DummyOperator(task_id='dummy_task', dag=dag)


t1 = SimpleHttpOperator(
    task_id='get_api_response',
    method='GET',
    http_conn_id='http_default',
    endpoint='/',
    headers={"Content-Type": "application/json"},
    xcom_push=True,
    log_response=True,
    dag=dag)

t2 = PythonOperator(
    task_id= 'python_parse',
    python_callable=parse,
    dag=dag
)

pull = PythonOperator(
    task_id='puller',
    dag=dag,
    python_callable=puller,
)

test = PythonOperator(
    task_id = 'httphooker',
    dag=dag,
    python_callable=httpcall
)

t1 >> t2 >> pull

