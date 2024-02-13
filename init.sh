#!/bin/bash

git init
git add .
echo Enter your comment: 
read comment 
git commit -m "$comment"
git branch -M main

