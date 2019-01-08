from datetime import datetime
from airflow import DAG
from airflow.operators.dummy_operator import DummyOperator
from airflow.operators import MyFirstOperator

dag = DAG('my_test_dag', description='Another tutorial DAG',
          schedule_interval=None,
          start_date=datetime(2017, 12, 12), catchup=False)

dummy_operator = DummyOperator(task_id='dummy_task', retries=3, dag=dag)

operator_task = MyFirstOperator(my_operator_param='This is a test.',
                                task_id='my_first_operator_task', dag=dag)

dummy_operator >> operator_task