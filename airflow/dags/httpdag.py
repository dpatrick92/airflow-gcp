from datetime import datetime
import airflow
from airflow import DAG
from airflow.operators.dummy_operator import DummyOperator
from airflow.operators.http_operator import SimpleHttpOperator
from airflow.operators.python_operator import PythonOperator
import requests
import config

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

t2 >> pull

