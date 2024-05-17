export $(cat .env | xargs)
terraform destroy -auto-approve