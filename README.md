# Miracle

A project I did to play around with Terraform deployment to AWS and networking between containers.

## Part 0: Create a .env file

Since this is not in production, I will just the .env here. Put it in the root of this repository:
```
TF_VAR_db_user=postgres
TF_VAR_db_name=postgres
TF_VAR_db_port=5432
TF_VAR_db_password=miraclepassword
TF_VAR_aws_account_id=862592418544
TF_VAR_aws_region=us-east-1
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
DATABASE_HOST=database
DATABASE_USER=postgres
DATABASE_PASSWORD=miraclepassword
DATABASE_NAME=postgres
DATABASE_PORT=5432
```

Replace `TF_VAR_aws_account_id` with your actual ID (you don't need to if you're not deploying with Terraform).

## Part 1: How to run locally

This project has been designed to run as easily as possible. All you need is Docker. In Terminal, run this command:
```
docker-compose up --build
```

After the database has started up (which might take a minute or less), the webscraper and website will start running. Access the website on your local browser at `localhost:3000`.

## Part 2: How to view your database (if you're interested)

Find the Docker `CONTAINER ID` of the container with the Postgres database:
```
docker ps
```

If the `CONTAINER ID` is c3c6fe42ec76, then run:
```
docker exec -it c3c6fe42ec76 psql -U postgres
```

You will need to install `psql` if you don't have it.

## Part 3: Architecture overview

There are 3 Docker containers: 1 for the database, 1 for the webscraper, and 1 for the website.

Database: the database has 2 tables, us and eu. These 2 tables simply drop in the scraped results without any modifications, because it is better to keep the data as close to the source as possible and make modifications afterwards. There is also a Postgres view called combined_view, which the scraper generates. This view generates a new row for each condition, so if a clinical trial covers five conditions, there will be five rows with the same study ID. This is so that conditions can be aggregated.

Webscraper: there are 2 scripts, us and eu. There is a parent script that schedules the scripts to run every 12 hours. The parent script generates the combined_view after us and eu are done scraping. The database functions are in a separate script, to make it easy to execute simple queries and reuse the database connection logic.

Website: this is a simple React Next.js website with 2 API functions, to query conditions and sponsors. The database connection logic is in a separate file to be reusable from all API functions. The data is shown as a simple bar chart from recharts.

Docker: by using Docker Compose, all containers are connected to the same "network", so can communicate with each other without extra networking work. The database's container has a volume, so that data can persist if the container stops. There are trade-offs between containerizing a database and putting on bare-metal like AWS RDS. For this project, it made more sense to put it in a container and immensely simplify the deployment process.

## Bonus Part 4: Deploy to AWS with Terraform

First, install Terraform: https://developer.hashicorp.com/terraform/install

Second, install AWS CLI 2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- In the AWS console,
- IAM
- Users on left
- Select a user
- Select Security credentials tab
- In the Access keys section, click "Create access key" button
- For use case, select Command Line Interface (CLI)
- Select the confirmation. AWS has new forms of authentication, but Terraform still suggests using the access key method: https://developer.hashicorp.com/terraform/tutorials/aws-get-started/aws-build
- Set optional description tag, press "Create access key" button
- In Terminal, run "aws configure"
- Copy and paste the access key and secret key into Terminal when prompted
- Press Enter in Terminal to skip the other configurations

Lastly, simply run the scripts in Terminal:
```
sh build_and_push_images.sh
sh deploy_infrastructure.sh
```

After a few minutes, everything should be deployed in the real cloud. In Terminal, you should see the link to the load balancer where you can access the frontend, like this `http://web-alb-1152114135.us-east-1.elb.amazonaws.com/`.

The Terraform AWS configuration will:
- Create an AWS VPC: the VPC has two public and two private subnets
- Create a load balancer, on the public subnet
- Create an ECS cluster: the cluster has 2 ECS services, one for each container, each service with a task definition
- Create an RDS Postgres database, with  its own private subnet
- The 2 ECS services, RDS database, and load balancer have a security group
- The subnets and security groups are configured such that the load balancer is public, the website and scraper are private, and the database only allows traffic from the website and scraper.

Note that this AWS deployment is different from the local deployment; instead of putting Postgres in a container, this creates a Postgres in RDS, and communication is done within the VPC instead of the Docker Compose network.

The website and database do not have HTTPS/SSL encryption. Encryption is essential for production, but for this project, no SSL certificates allows easier deployment both locally and on AWS without extra configuration.
