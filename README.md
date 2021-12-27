aws2icinga2
=====================
Generate and synchronize hosts from an AWS account to Icinga2 via API.

    AWS API -> script -> Icinga2 API


Available services
------------------
  These are the available service types to sync from. See below how to choose services for sync with `CONFIG_SERVICE`.

|Servicetype (config)|Description|
|---|---|
|**ec2**|Elastic Compute Cloud|
|**autoscaling**|AutoScaling groups from ec2|
|**elb**|Elastic Load Balancing|
|**alb**|Application Load Balancer aka elb v2. This will generate **alb-targetgroup** as well|
|**elasticache**|ElastiCache|
|**vpn**|VPC VPN|

Created host object - Available variables
--------------
Each servicetype can add several additional vars (see below).
However, this tool will set the following host variables:

### Generic vars
|Variable|Example|Description|
|---|---|---|
|import template|generic-host|**Fixed** The Icinga2 template to apply|
|check_command|hostalive or dummy|**Fixed** Which check command to apply on this "host"|
|vars.package|aws-tracking|Represents the configured $CONFIG_PACKAGE_NAME|
|vars.aws.type|ec2|Servicetype|
|vars.aws.id|test123|Id or Name of this service in this account (**Not global unique!**)|
|vars.aws.region|eu-central-1|AWS Region of this Service|
|vars.aws.arn|arn:aws:elasticloadbalancing:eu-central-1:369653696549:targetgroup/tag-manager-core/85e44a125935e00c|**Optional** If available sets the global Amazon Resource Names (ARNs)|
|vars.aws.public_ip|54.1.1.1.1|**Optional** Public IP|
|vars.aws.private_ip|10.1.2.3|**Optional** Private IP|
|vars.aws.public_dns|ec2-1-2-3-4.eu-central-1.compute.amazonaws.com|**Optional** Public DNS|
|vars.aws.private_dns|ip-10-1-2-3.eu-central-1.compute.internal|**Optional** Private DNS|
|vars.aws.instance_type|t2.small|**Optional** Instance type|
|vars.aws.availability_zones|[ "eu-central-1a" ]|**Optional** Array of AZs which this service is located|
|vars.aws.tags[Key]=Value|{Name = "test-a-b"}|Hash/Dictionary of all configured tags|

### "ec2" vars
```
vars.aws.ec2 = {
  block_devices = [ "/dev/sda1" ]
  launch_time = 1501957383.000000
}
```

### "autoscaling" vars
```
autoscaling = {
  default_cooldown = 300.000000
  desired_capacity = 4.000000
  health_check_type = "EC2"
  load_balancer_names = [ "mytestlb" ]
  max_size = 4.000000
  min_size = 4.000000
  target_group_arns = [ ]
}
```

### "elb" vars
```
elb = {
  listener = {
    HTTP = {
      "80" = {
        ssl_certificate_id = null
      }
    }
    HTTPS = {
      "443" = {
        ssl_certificate_id = "arn:aws:iam::360264906649:server-certificate/wildcard.test.com"
      }
    }
  }
  scheme = "internet-facing"
}
```

### "alb" vars
```
alb = {
  listener = {
    HTTP = {
      "80" = {
        arn = "arn:aws:elasticloadbalancing:eu-central-1:364654366649:listener/app/myapp/de8c935cbr8e89e6/19959a7e710b9052"
        certificates = [ ]
        ssl_policy = null
      }
    }
    HTTPS = {
      "443" = {
        arn = "arn:aws:elasticloadbalancing:eu-central-1:362654304649:listener/app/myapp/de8c935c698e89b6/3748f280b29d8a97"
        certificates = [ {
          certificate_arn = "arn:aws:iam::369444306649:server-certificate/wildcard.test.com"
        } ]
        ssl_policy = "ELBSecurityPolicy-2015-05"
      }
    }
  }
  scheme = "internet-facing"
  target_groups = {
    "tag-manager-core" = {
      arn = "arn:aws:elasticloadbalancing:eu-central-1:369654306649:targetgroup/myapp/85e44a125235e00c"
    }
    "tag-manager-pixel" = {
      arn = "arn:aws:elasticloadbalancing:eu-central-1:369654306649:targetgroup/myapp/84b767bd29e1a5ee"
    }
  }
}
```

### "alb-targetgroup" vars
```
"alb-targetgroup" = {
  healthy_threshold_count = 5.000000
  load_balancer_arns = [ "arn:aws:elasticloadbalancing:eu-central-1:369654306649:loadbalancer/app/myapp/de4c935cb98e89b6" ]
  port = 80.000000
  protocol = "HTTP"
  unhealthy_threshold_count = 2.000000
}
```

### "elasticache" vars
```
elasticache = {
  engine = "redis"
  engine_version = "3.2.4"
  num_node = 1.000000
  port = 6379.000000
}
```

### "vpn" vars
```
vpn = {
  customer_gateway_id = "cgw-f90ee3c9"
  gateways = [ "54.1.2.3", "54.1.2.3" ]
  type = "ipsec.1"
  vpn_gateway_id = "vgw-2fea871f"
}
```

Configuration Environment Variables
-----------------------------------
All Available Environment variables to customize this tool

### Used by this tool
  Customize for your needs.

|Variable|Description|
|---|---|
|**CONFIG_PACKAGE_NAME**|**Required** Define an unique name to separate different accounts with same region. Generates something like CONFIG_PACKAGE_NAME + AWS_REGION|
|**CONFIG_SERVICES**|**Required** Comma separated list of AWS services to synchronize. Example: `ec2,elb,elasticache`|
|**CONFIG_EC2_IGNORE_AUTOSCALING**|**Optional** Set to any value to enable ignore - Do not add autoscaling instaces. *Default* not set = disabled|
|**CONFIG_EC2_TAG_NAME**|**Optional** This tag key will be used to inject the value in the display_name. *Default* not set = disabled|
|**CONFIG_IGNORE_TAGS**|**Optional** Comma separated list of resources to ignore if one of the tags matches. Example `CONFIG_IGNORE_TAGS="environment"="development",monitoring=disabled`|
|**CONFIG_VARS_HOST**|**Optional** Merge object vars to host. JSON values (escaped if required). Example `CONFIG_VARS_HOST="{\"team\": [\"tracking\"]}"`|

### AWS
  These are the required settings for the AWS API connection.
  The User needs at minimum read access to services to get all informations.

|Variable|Description|
|---|---|
|**AWS_REGION**|**Required** AWS region to use|
|**AWS_ACCESS_KEY_ID**|**Required** AWS access key of the used account|
|**AWS_SECRET_ACCESS_KEY**|**Required** AWS secret key of the used account|

### Icinga2 API
  Connect to icinga2 via this credentials and URL.

|Variable|Description|Default|
|---|---|---|
|**ICINGA_ZONE**|**Optional** Assign objects to this icinga2 zone |not set|
|**ICINGA_API_USERNAME**|**Optional** API username|root|
|**ICINGA_API_PASSWORD**|**Optional** API password|icinga|
|**ICINGA_API_URL_BASE**|**Optional** Base URL|https://127.0.0.1:5665/v1|

Setup
-----
  Install required gems: `bundle install --deployment --without development test`

### Icinga2
  For config sync in cluster (zones) set `accept_config` to `true`

  ```
  object ApiListener "api" {
    cert_path = SysconfDir + "/icinga2/pki/" + NodeName + ".crt"
    key_path = SysconfDir + "/icinga2/pki/" + NodeName + ".key"
    ca_path = SysconfDir + "/icinga2/pki/ca.crt"
    accept_config = true
  }
  ```

Features / to do's
-------------

  * [ ] Support multiple regions
  * [ ] Provide delete flag to cleanup a package from icinga2
  * [ ] Improve get hosts list from icinga2 by limiting the returned attributs
  * [ ] Improve logging
  * [ ] Support AWS SNS for config changes (turn into daemon)
    * [ ] Add HTTP Endpoint for SNS (per region?)
    * [ ] Only trigger update for the affected service/object
