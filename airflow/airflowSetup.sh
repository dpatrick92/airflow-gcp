#!/bin/bash -xe

# Proxy to Cloud SQL must be configured
# Set AIRFLOW_HOME env variable for root
export PROXY_HOME=/opt/cloud_sql_proxy

if grep -q true "$PROXY_HOME/script_ran"; then
    # Start the CloudSQL proxy specifying the database instance to connect to.
    cd $PROXY_HOME
    nohup ./cloud_sql_proxy -instances=mindful-silo-222216:us-central1:my-airflow-db=tcp:0.0.0.0:5432 &
else
    #Set timezone for logging purposes
    echo "America/New_York" > /etc/timezone
    dpkg-reconfigure -f noninteractive tzdata

    #Set env variable for other users
    sudo echo PROXY_HOME=/opt/cloud_sql_proxy >> /etc/environment

    # Download the proxy and make it executable.
    sudo mkdir $PROXY_HOME
    sudo chmod 777 $PROXY_HOME
    cd $PROXY_HOME
    sudo wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
    sudo chmod +x $PROXY_HOME/cloud_sql_proxy

    #Set SCRIPT_RAN env variable to true so this doesnt run again
    sudo echo true >> $PROXY_HOME/script_ran

    # Start the CloudSQL proxy specifying the database instance to connect to.
    cd $PROXY_HOME
    nohup ./cloud_sql_proxy -instances=mindful-silo-222216:us-central1:my-airflow-db=tcp:5432 &
fi

# Install and configure airflow

#Set AIRFLOW_HOME env variable for root
export AIRFLOW_HOME=/airflow
export ENV=development
# New GPL dependency in 1.10, avoiding this lib due to licensing concerns
export SLUGIFY_USES_TEXT_UNIDECODE=yes

if grep -q true "$AIRFLOW_HOME/script_ran"; then
    # Start airflow
    systemctl start airflow-scheduler
    systemctl start airflow-webserver
else
    # Set timezone for logging purposes
    echo "America/New_York" > /etc/timezone
    dpkg-reconfigure -f noninteractive tzdata

    # Initialize service  (comment out for default)
    #gcloud init --account airflow-vm@slalom-technical-solutions.iam.gserviceaccount.com --project slalom-technical-solutions


    # Packages necessary for development
    sudo apt-get update && sudo apt-get install -y \
    python-dev \
    build-essential \
    libssl-dev \
    libffi-dev \
    git \
    postgresql-client \
    unixodbc \
    unixodbc-dev \

    # install pip
    wget https://bootstrap.pypa.io/get-pip.py
    sudo python2 get-pip.py
    sudo rm get-pip.py

    # Set env variable for other users
    sudo echo AIRFLOW_HOME=/airflow >> /etc/environment
    sudo echo ENV=development >> /etc/environment
    sudo echo SLUGIFY_USES_TEXT_UNIDECODE=yes >> /etc/environment

    # Upgrade core lib
    pip install --upgrade setuptools
    # cryptography pacakge necessary to encrypt passwords stored in airflow
    sudo pip install cryptography
    # Python + Postgres lib
    sudo pip install psycopg2
    # Install apache-beam packages
    sudo pip install apache-beam


    # Install Airflow with the extra package gcp_api containing the hooks and operators for the GCP services.
    sudo SLUGIFY_USES_TEXT_UNIDECODE=yes pip install "apache-airflow[crypto, gcp_api, ldap, postgres, password]==1.10.0"

    # Create AIRFLOW_HOME directory.
    sudo mkdir $AIRFLOW_HOME
    sudo chmod 777 $AIRFLOW_HOME
    cd $AIRFLOW_HOME

    # Sync config, dags and plugins from repo
	#CHANGING THIS TO RSYNC
    gsutil rsync -d -r gs://my-airflow-bucket/airflow/ .

    # setup a cron task to keep this folder in sync
    #echo '#!/bin/bash' >> dagscronjob.sh
    #echo 'sudo git --git-dir=/airflow/.git pull' >> dagscronjob.sh
    #chmod +x dagscronjob.sh
    #echo '*/30 * * * * /airflow/dagscronjob.sh' >> cronfile

    # Run Airflow a first time to create the airflow.cfg configuration file and edit it.
    airflow version
	
	
	
    # setup airflow to work with systemd as a service
    sudo cp $AIRFLOW_HOME/config/airflow-scheduler.service /lib/systemd/system/airflow-scheduler.service
    sudo cp $AIRFLOW_HOME/config/airflow-webserver.service /lib/systemd/system/airflow-webserver.service
    # re-register systemd daemon
    systemctl daemon-reload
    # Make sure Airflow uses a Sequential executor
    sudo sed -i 's;SequentialExecutor;LocalExecutor;g' $AIRFLOW_HOME/airflow.cfg
    # connection to Airflow DB; Use the name of the CloudSQL Database that you set up
    sudo sed -i 's;sqlite:////airflow/airflow.db;postgresql+psycopg2://airflow:airflow123!@127.0.0.1:5432/airflowdb;g' $AIRFLOW_HOME/airflow.cfg
    # Prevents loading example DAGs
    sudo sed -i 's;load_examples = True;load_examples = False;g' $AIRFLOW_HOME/airflow.cfg
    # Make sure the key stays consistent so we can decrypt all our connection keys. This was generated beforehand
    #sudo sed -i '/fernet_key =/c\fernet_key = uZSlnAweEwsKiboeQA83Q4osl32JdBJ8-fetsNJbRqQ=' $AIRFLOW_HOME/airflow.cfg
    # Update a few airflow properties to increase concurrency and reduce wait time for task instances by speeding up the heartbeat from 5s
    sudo sed -i '/parallelism =/c\parallelism = 256' $AIRFLOW_HOME/airflow.cfg
    sudo sed -i '/dag_concurrency =/c\dag_concurrency = 64' $AIRFLOW_HOME/airflow.cfg
    sudo sed -i '/scheduler_heartbeat_sec =/c\scheduler_heartbeat_sec = 2' $AIRFLOW_HOME/airflow.cfg
    # Required changes for remote_logging
	airflow connections --add --conn_id=gcp_logging_connection --conn_type=google_cloud_platform --conn_extra='{ "extra__google_cloud_platform__project": "mindful-silo-222216", "extra__google_cloud_platform__scope": "https://www.googleapis.com/auth/cloud-platform"}' 
    sudo sed -i 's;remote_log_conn_id =;remote_log_conn_id = gcp_logging_connection\n;g' $AIRFLOW_HOME/airflow.cfg
    sudo sed -i 's;remote_logging = False;remote_logging = True;g' $AIRFLOW_HOME/airflow.cfg
    sudo sed -i 's;remote_base_log_folder =;remote_base_log_folder = gs://my-airflow-bucket/logs;g' $AIRFLOW_HOME/airflow.cfg
    sudo sed -i '/remote_logging = True/ i\GCS_LOG_FOLDER = gs://my-airflow-bucket/logs/' $AIRFLOW_HOME/airflow.cfg


    # Create cron job to restart airflow-scheduler day, 4am UTC = 12am EST
    # This is a best practice to keep scheduler and webserver running smoothly
    echo '0 4 * * * /bin/systemctl restart airflow-scheduler.service' >> cronfile
    echo '0 4 * * * /bin/systemctl restart airflow-webserver.service' >> cronfile

    crontab cronfile
    rm cronfile

    sudo service cron start

    # Run Airflow again to initialize the metadata database.
    airflow initdb

    # Start the airflow scheduler and webserver
    systemctl start airflow-scheduler
    systemctl start airflow-webserver

    # Set SCRIPT_RAN env variable to true so this doesnt run again
    sudo echo true >> $AIRFLOW_HOME/script_ran
fi