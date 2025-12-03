Goal: to create a web scraper using selenium running on a container as an aws lambda.

Prerequisite: some basic knowledge of [aws lambda](https://www.datacamp.com/tutorial/aws-lambda), docker, and web scraper based on selenium running locally.

(Note that this is written a few weeks after I successfully deployed my lambda function and may contain some inaccuracy.)

When one's lambda function uses something more than the built-in python libraries, one has to create either a lambda layer or a container image to satisfy the requirements (dependencies). We will take the latter approach since the selenium and the accompanying chrome executable files are too huge for a thin lambda layer.

The project [docker-selenium-lambda](https://github.com/umihico/docker-selenium-lambda) gives us a good starting point. At first, I wasted quite some time getting stuck at "sls" which I never knew before. Then I realized that we can do without sls at all. It's sufficient to use just the docker file from the above datacamp project.

Here are the steps that I have taken.
**Be sure to read the shell scripts and set/modify the environment variables before executing them!**
1. Create the heavyweight selenium container "base" image: ```docker build -f Dockerfile.base -t selenium-lambda .```
2. Grant the AmazonEC2ContainerRegistryReadOnly permission to the role running the lambda (mine is named "lambda_worker").
3. Send the image to the elastic container repository (ECR) of aws: ```./deploy_base.sh```
4. Write/modify the lambda handler albscraper.py .
5. Create a thin (lightweight) docker image based on (derived from) the heavy base image, differing only in the above lambda function, and deploy it: ```./deploy_thin_lambda.sh albscraper``` This greatly reduces the time for uploading the image, as compared to the case where one has a single heavy container image to upload for every small change to albscraper.py .
6. Add this: ```cli_pager = cat``` in ~/.aws/config . By default, ```aws lambda invoke ...``` sends its output to the less pager, which requires human interaction and therefore results in seeming hang when it appears in a script.
7. Test from the command line: ```do_part.sh stock_listing.txt```
8. Repeat steps 3-5 until satisfied.

Additional notes about the process:
1. I had issues with ```aws lambda update-function-code ...``` . In my working cycle of updating .py, rebuilding the docker image, sending it to ECR, and testing, the version that aws lambda runs seems to be 1 or 2 versions lagging behind. I use ```aws lambda get-function --query 'Configuration.ImageUri' ...``` to verify that aws lambda sees the same image as the one I have in my local desktop. Somehow the problem goes away when I do this.
2. The wait (```sleep 10```) between two aws lambda invocations in the loop is essential. Immediate successive invocations may result in SessionNotCreatedException regardless of the lambda resource (memory and disk) allocation.

Notes about albscraper.py:
1. This script can be tested locally. My desktop is debian trixie. I have installed chromium and chromium-driver, and created two sym links: ```ln -s /usr/bin/chromium chrome``` and ```ln -s /usr/bin/chromedriver /opt/chromedriver``` so that these executables have the same paths as their counterparts in the docker image.
2. The script expects a few config parameters in the payload file:
   - to_do: the object name (file name) of a text file containing one "page id" on each line
   - s3_path: s3 path of a directory where the above to_do file is uploaded in advance and where retrieved html files are stored
   - url_template: a url template that looks like this: ```https://example.com/stock/eps/{page_id}.html```
   - delay: delay between two page retrievals, in seconds
   - count: number of page id's to process for each aws lambda invocation
3. The script looks at the to_do list, tries to retrieve the pages specified by the first few page_id's, store them in s3_path, removes these page id's, and store the shortened list back to the to_do file.
