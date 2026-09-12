# Remediation patterns

Fix snippets per layer, for AWS CDK (TypeScript), Terraform and SAM/CloudFormation. Read
only the sections for the layers you are actually fixing.

These are starting points, not drop-in replacements. Match the surrounding code's style,
naming and construct versions, and change only what the approved finding calls for.

**Before editing anything:** the fix is approved, the change is minimal, and the user knows
its blast radius. After editing: show the diff, run the project's validation
(`cdk synth`, `terraform validate`, `sam validate`, `cfn-lint`, linters, tests), and say
what still needs a deploy.

---

## Layer 1 — WAF

**CDK**

```ts
const webAcl = new wafv2.CfnWebACL(this, 'ApiWebAcl', {
  scope: 'REGIONAL',
  defaultAction: { allow: {} },
  visibilityConfig: {
    cloudWatchMetricsEnabled: true,
    metricName: 'ApiWebAcl',
    sampledRequestsEnabled: true,
  },
  rules: [
    {
      name: 'AWSManagedRulesCommonRuleSet',
      priority: 1,
      overrideAction: { none: {} }, // 'none' = the managed rule's own action (Block) applies
      statement: {
        managedRuleGroupStatement: { vendorName: 'AWS', name: 'AWSManagedRulesCommonRuleSet' },
      },
      visibilityConfig: {
        cloudWatchMetricsEnabled: true, metricName: 'CommonRuleSet', sampledRequestsEnabled: true,
      },
    },
    {
      name: 'RateLimit',
      priority: 2,
      action: { block: {} },
      statement: {
        rateBasedStatement: { limit: 2000, aggregateKeyType: 'IP' },
      },
      visibilityConfig: {
        cloudWatchMetricsEnabled: true, metricName: 'RateLimit', sampledRequestsEnabled: true,
      },
    },
  ],
});

new wafv2.CfnWebACLAssociation(this, 'ApiWebAclAssoc', {
  resourceArn: `arn:aws:apigateway:${Stack.of(this).region}::/restapis/${api.restApiId}/stages/${api.deploymentStage.stageName}`,
  webAclArn: webAcl.attrArn,
});
```

Rolling a WAF out in front of live traffic deserves a Count-mode period first. Say this to
the user: put the managed rule group in Count, watch the sampled requests for false
positives, then switch to Block. Going straight to Block on a production API can break
legitimate requests.

**Terraform**

```hcl
resource "aws_wafv2_web_acl" "api" {
  name  = "api-web-acl"
  scope = "REGIONAL"

  default_action { allow {} }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "api-web-acl"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_api_gateway_stage.api.arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}
```

---

## Layer 2 — Cognito

**CDK**

```ts
const userPool = new cognito.UserPool(this, 'UserPool', {
  selfSignUpEnabled: false,
  signInAliases: { email: true },
  mfa: cognito.Mfa.REQUIRED,
  mfaSecondFactor: { sms: false, otp: true },
  passwordPolicy: {
    minLength: 12,
    requireLowercase: true,
    requireUppercase: true,
    requireDigits: true,
    requireSymbols: true,
  },
  accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
  advancedSecurityMode: cognito.AdvancedSecurityMode.ENFORCED,
  removalPolicy: RemovalPolicy.RETAIN,
});

userPool.addClient('WebClient', {
  authFlows: { userSrp: true },           // not userPassword
  accessTokenValidity: Duration.minutes(60),
  idTokenValidity: Duration.minutes(60),
  refreshTokenValidity: Duration.days(30),
  preventUserExistenceErrors: true,
  oAuth: {
    flows: { authorizationCodeGrant: true },  // not implicitCodeGrant
    callbackUrls: ['https://app.example.com/callback'],
  },
});
```

Two warnings to pass on: `Mfa.REQUIRED` on an existing pool affects sign-in for current
users, who need an enrolment path first — `OPTIONAL` plus an enrolment campaign is often
the workable order. And `advancedSecurityMode` carries additional cost per monthly active
user.

---

## Layer 3 — API Gateway

**CDK**

```ts
const api = new apigateway.RestApi(this, 'Api', {
  endpointConfiguration: { types: [apigateway.EndpointType.REGIONAL] },
  deployOptions: {
    throttlingRateLimit: 100,
    throttlingBurstLimit: 200,
    loggingLevel: apigateway.MethodLoggingLevel.ERROR,
    accessLogDestination: new apigateway.LogGroupLogDestination(accessLogGroup),
    accessLogFormat: apigateway.AccessLogFormat.jsonWithStandardFields(),
    metricsEnabled: true,
  },
});

const authorizer = new apigateway.CognitoUserPoolsAuthorizer(this, 'Authorizer', {
  cognitoUserPools: [userPool],
});

const model = api.addModel('CreateItemModel', {
  contentType: 'application/json',
  schema: {
    type: apigateway.JsonSchemaType.OBJECT,
    required: ['name'],
    properties: {
      name: { type: apigateway.JsonSchemaType.STRING, maxLength: 120 },
    },
    additionalProperties: false,
  },
});

items.addMethod('POST', new apigateway.LambdaIntegration(fn), {
  authorizer,
  authorizationType: apigateway.AuthorizationType.COGNITO,
  requestModels: { 'application/json': model },
  requestValidator: new apigateway.RequestValidator(this, 'Validator', {
    restApi: api, validateRequestBody: true, validateRequestParameters: true,
  }),
});
```

**SAM / CloudFormation**

```yaml
Globals:
  Api:
    Auth:
      DefaultAuthorizer: CognitoAuthorizer
      Authorizers:
        CognitoAuthorizer:
          UserPoolArn: !GetAtt UserPool.Arn
    MethodSettings:
      - ResourcePath: "/*"
        HttpMethod: "*"
        ThrottlingRateLimit: 100
        ThrottlingBurstLimit: 200
        LoggingLevel: ERROR
    TracingEnabled: true
```

Adding an authorizer to a route that was previously open **breaks every existing client of
that route**. Flag it, and check with the user whether any caller exists that cannot send a
token yet.

---

## Layer 4 — Network

**CDK** — least-privilege security groups and VPC endpoints:

```ts
const lambdaSg = new ec2.SecurityGroup(this, 'LambdaSg', { vpc, allowAllOutbound: false });
const dbSg = new ec2.SecurityGroup(this, 'DbSg', { vpc, allowAllOutbound: false });

dbSg.addIngressRule(lambdaSg, ec2.Port.tcp(5432), 'Lambda to Postgres');
lambdaSg.addEgressRule(dbSg, ec2.Port.tcp(5432), 'Postgres');

vpc.addGatewayEndpoint('DynamoEndpoint', { service: ec2.GatewayVpcEndpointAwsService.DYNAMODB });
vpc.addInterfaceEndpoint('SecretsEndpoint', {
  service: ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER,
});

fn.connections.allowTo(dbSg, ec2.Port.tcp(5432));
```

`allowAllOutbound: false` on an existing function will break any outbound call you have not
explicitly allowed — including calls to AWS APIs that have no VPC endpoint. Enumerate the
function's outbound dependencies with the user before flipping it.

**Terraform** — replacing an open ingress rule:

```hcl
resource "aws_security_group_rule" "db_from_app" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.app.id   # was cidr_blocks = ["0.0.0.0/0"]
  description              = "App tier to Postgres"
}
```

---

## Layer 5 — Lambda and IAM

**CDK** — scoped execution role, replacing a wildcard grant:

```ts
// Prefer the grant helpers: they scope the action and the resource for you.
table.grantReadWriteData(fn);            // not new PolicyStatement({ actions: ['dynamodb:*'] })
secret.grantRead(fn);
bucket.grantRead(fn, 'uploads/*');

// When a raw statement is unavoidable, scope both action and resource:
fn.addToRolePolicy(new iam.PolicyStatement({
  actions: ['dynamodb:Query', 'dynamodb:GetItem'],
  resources: [table.tableArn, `${table.tableArn}/index/*`],
  conditions: {
    'ForAllValues:StringEquals': {
      'dynamodb:LeadingKeys': ['${aws:userid}'],
    },
  },
}));
```

Removing a Lambda Function URL that was `AuthType: NONE`:

```ts
// Delete the addFunctionUrl(...) call and route through API Gateway with an authorizer.
// If the URL must stay, at minimum:
fn.addFunctionUrl({ authType: lambda.FunctionUrlAuthType.AWS_IAM });
```

Replacing an environment-variable secret with a runtime fetch:

```ts
const secret = secretsmanager.Secret.fromSecretNameV2(this, 'DbSecret', 'prod/db');
secret.grantRead(fn);
fn.addEnvironment('DB_SECRET_NAME', 'prod/db');   // the name, never the value
```

```ts
// In the function, fetched once per container, not once per invocation:
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
const client = new SecretsManagerClient({});
let cached: string | undefined;

async function getSecret(): Promise<string> {
  if (!cached) {
    const res = await client.send(new GetSecretValueCommand({ SecretId: process.env.DB_SECRET_NAME! }));
    cached = res.SecretString!;
  }
  return cached;
}
```

---

## Layer 6 — Secrets

**CDK** — a generated, rotated secret:

```ts
const dbSecret = new secretsmanager.Secret(this, 'DbSecret', {
  generateSecretString: {
    secretStringTemplate: JSON.stringify({ username: 'app' }),
    generateStringKey: 'password',
    excludePunctuation: true,
    passwordLength: 32,
  },
  removalPolicy: RemovalPolicy.RETAIN,
});

dbSecret.addRotationSchedule('Rotation', {
  hostedRotation: secretsmanager.HostedRotation.postgreSqlSingleUser(),
  automaticallyAfter: Duration.days(30),
});
```

**When the finding is a hardcoded credential, the order of operations is not optional:**

1. The user rotates the credential in the provider (AWS, the database, the third party).
2. The new value goes into Secrets Manager — by the user, through their own console or CLI.
   Do not ask the user to paste a secret into the chat, and do not write one into a file.
3. Then the code change: remove the literal, read from Secrets Manager at runtime.
4. Tell the user the old value stays in git history and treat it as burned regardless.

---

## Layer 7 — Data

**CDK**

```ts
const table = new dynamodb.Table(this, 'Table', {
  partitionKey: { name: 'pk', type: dynamodb.AttributeType.STRING },
  encryption: dynamodb.TableEncryption.CUSTOMER_MANAGED,
  encryptionKey: key,
  pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true },
  deletionProtection: true,
  removalPolicy: RemovalPolicy.RETAIN,
});

const bucket = new s3.Bucket(this, 'Bucket', {
  blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
  encryption: s3.BucketEncryption.KMS,
  encryptionKey: key,
  enforceSSL: true,
  versioned: true,
  removalPolicy: RemovalPolicy.RETAIN,
});
```

Switching an existing DynamoDB table to a customer-managed key is an update in place, but
changing the partition key or the table name **replaces the table and destroys the data**.
Before any change to a stateful resource, check what the framework will do — `cdk diff`,
`terraform plan` (read-only, no state write) — and tell the user if replacement is on the
table. This is the single most dangerous class of "security fix".

---

## Continuous monitoring

**CDK**

```ts
new cloudtrail.Trail(this, 'Trail', {
  isMultiRegionTrail: true,
  enableFileValidation: true,
  managementEvents: cloudtrail.ReadWriteType.ALL,
  sendToCloudWatchLogs: true,
});

new guardduty.CfnDetector(this, 'GuardDuty', {
  enable: true,
  findingPublishingFrequency: 'FIFTEEN_MINUTES',
});
```

**Terraform** — routing findings somewhere a human sees them:

```hcl
resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name = "guardduty-high-severity"
  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail      = { severity = [{ numeric = [">=", 7] }] }
  })
}

resource "aws_cloudwatch_event_target" "to_sns" {
  rule = aws_cloudwatch_event_rule.guardduty_high.name
  arn  = aws_sns_topic.security_alerts.arn
}
```

GuardDuty and CloudTrail data events both cost money that scales with activity. Mention the
cost dimension when recommending them, rather than leaving the user to discover it on the
next invoice.
