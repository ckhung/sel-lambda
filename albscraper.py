# aws s3 batch scraper

from selenium import webdriver
from tempfile import mkdtemp
from selenium.webdriver.common.by import By
import time, boto3, json, re

s3 = boto3.client('s3')

def obj_serializer(obj):
    return vars(obj) if hasattr(obj, '__dict__') else repr(obj)

def reap(url_template, id_list, s3_bucket, s3_prefix, delay=5):
    global s3
    options = webdriver.ChromeOptions()
    service = webdriver.ChromeService("/opt/chromedriver")

    options.binary_location = '/opt/chrome/chrome'
    options.add_argument("--headless=new")
    options.add_argument('--no-sandbox')
    options.add_argument("--disable-gpu")
    options.add_argument("--window-size=800,600")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-dev-tools")
    options.add_argument("--no-zygote")

    chrome = webdriver.Chrome(options=options, service=service)
    for page_id in id_list:
        chrome.get(re.sub(r'\{page_id\}', page_id, url_template))
        time.sleep(delay)
        s3.put_object(Bucket=s3_bucket, Key=s3_prefix+page_id+'.html', Body=chrome.page_source.encode('utf-8'))
    chrome.quit()

def lambda_handler(event={}, context={}):
    global s3
    args = {}
    args['count'] = int(event.get('count', 5))
    args['delay'] = int(event.get('delay', 5))
    args['url_template'] = event.get('url_template')
    args['s3_path'] = event.get('s3_path')
    args['to_do'] = event.get('to_do')
    m = re.match(r's3://(\w+)/(.*)', args['s3_path'])
    s3_bucket, s3_prefix = m.group(1), m.group(2)
    if s3_prefix[-1] != '/': s3_prefix += '/'
    if type(args['to_do']) is list:
        # interpreted as a list of page ids
        listing = args['to_do']
    else:
        assert(type(args['to_do']) is str)
        # interpreted as the name of an s3 object (file) containing a list of page ids
        listing = s3.get_object(Bucket=s3_bucket, Key=s3_prefix+args['to_do'])
        listing = listing['Body'].read().decode('utf-8')
        listing = listing.splitlines()
    all_ids = []
    for item in listing:
        m = re.match(r'^(\w{3,})$', item)
        if m:
            all_ids.append(m.group(1))
    this_batch = listing[:args['count']]
    all_ids = listing[args['count']:]
    if type(args['to_do']) is str:
        s3.put_object(Bucket=s3_bucket, Key=s3_prefix+args['to_do'], Body='\n'.join(all_ids).encode('utf-8'))
    reap(args['url_template'], this_batch, s3_bucket, s3_prefix, args['delay'])

    return {
        'event': event,
        'this_batch': this_batch,
        'len(all_ids)': len(all_ids),
        'all_ids[0]': all_ids[0] if len(all_ids)>0 else '',
        'context': json.loads(json.dumps(context, default=obj_serializer))
    }

if __name__ == "__main__":
    with open('payload.json') as f:
        lambda_handler(event=json.load(f))

