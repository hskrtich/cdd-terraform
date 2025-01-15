# CDD Terraform

A super simple terraform project to create 2 services that are hosted in aws ecr and use ecs + alb to run. These services are behind a security group that only allows certin whitelisted cidrs.

## Prompt
> A developer has created two services for generating PDFs: one from web pages and the other from SVG files. These services should be deployed as images in ECR, individually for each service, and are written to use a REST-like API called by the main application. Please provide Terraform code to deploy these services in a secure way to AWS. They are accessible from only a set of machines called "production" (hosted on AWS) and another set called "quality" (hosted in a non-AWS datacenter). Please ask questions to clarify requirements. If you use AI tools, please describe how you used them.
