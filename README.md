# Mockexchange EKS IAC
A POC terraform module for https://mockexchange.test.trivialepic.com
## Submodules
### Network
Common VPC configuration
### Cluster
EKS Fargate cluster
### Database
RDS Aurora cluster (serverless) 
### Services
Spring Boot microservices deployed on EKS load balanced behind an owned domain 
### UI
S3 bucket and Cloudfront distribution behind an owned domain
