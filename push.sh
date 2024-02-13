#!/bin/bash

git add .
echo Enter your comment: 
read comment 
git commit -m "$comment"
git push -u origin main
git status

