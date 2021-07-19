import * as cdk from '@aws-cdk/core';

import * as kms from '@aws-cdk/aws-kms';
import * as s3 from '@aws-cdk/aws-s3';
import * as ssm from '@aws-cdk/aws-ssm';

import { BlockPublicAccess, StorageClass } from '@aws-cdk/aws-s3';
import { Duration, RemovalPolicy } from '@aws-cdk/core';
import { ParameterType } from '@aws-cdk/aws-ssm';

export interface LaptopBackupStackProps extends cdk.StackProps {
  projectName: string;
}

export class LaptopBackupStack extends cdk.Stack {
  constructor(scope: cdk.Construct, id: string, props: LaptopBackupStackProps) {
    super(scope, id, props);

    const backupKmsKey = new kms.Key(this, 'backupKey', {
      removalPolicy: RemovalPolicy.DESTROY,
      pendingWindow: Duration.days(7),
    });

    const backupBucket = new s3.Bucket(this, 'backupBucket', {
      bucketName: cdk.PhysicalName.GENERATE_IF_NEEDED,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: backupKmsKey,
      enforceSSL: true,
      lifecycleRules: [
        {
          abortIncompleteMultipartUploadAfter: Duration.days(10),
          transitions: [
            {
              storageClass: StorageClass.INTELLIGENT_TIERING,
              transitionAfter: Duration.days(30),
            },
            {
              storageClass: StorageClass.GLACIER,
              transitionAfter: Duration.days(180),
            },
          ],
          noncurrentVersionTransitions: [
            {
              storageClass: StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30),
            },
            {
              storageClass: StorageClass.GLACIER,
              transitionAfter: Duration.days(60),
            },
          ],
        },
      ],
      publicReadAccess: false,
      blockPublicAccess: BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.RETAIN,
      versioned: true,
    });

    const bucketNameParameter = new ssm.StringParameter(
      this,
      'backupBucketNameParameter',
      {
        stringValue: backupBucket.bucketName,
        type: ParameterType.STRING,
      }
    );
  }
}
