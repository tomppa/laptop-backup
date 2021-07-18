#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from '@aws-cdk/core';
import { LaptopBackupStack } from '../lib/laptop-backup-stack';

export type Environment = {
  projectName: string;
};

const app = new cdk.App();
const projectName: string = app.node.tryGetContext('projectName');

const env: Environment = {
  projectName,
};

const laptopBackupStack = new LaptopBackupStack(app, 'laptopBackupStack', env);
