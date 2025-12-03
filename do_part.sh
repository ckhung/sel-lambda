#!/bin/bash

part_file=$1
part_name=${part_file/*\//}
part_name=${part_name/.*/}
batch_size=5
export AWS_CLI_READ_TIMEOUT=960
export AWS_PAGER=''
part_length=$(grep -P '^\d{4}' $part_file | wc -l)
batch_count=$(((part_length - 1) / batch_size + 1))
echo "processing '$part_file' as $batch_count batches of size $batch_size..."
aws s3 cp $part_file $S3_STOCK/raw/div/
for ((i=0; i<batch_count; ++i)); do
    echo -n "$i : "; date
    pp_i=$(perl -e "printf('%03d', $i)")
    perl -pe "s#URL_TEMPLATE#$STOCK_DIV_URL_TMP#; s#S3_PATH#$S3_STOCK/raw/div/#; s#TO_DO_FN#$part_file#" payload_template.json > payload_${part_name}.json
    aws lambda invoke --function-name albscraper --cli-binary-format raw-in-base64-out --payload file://payload_${part_name}.json log_${part_name}_${pp_i}.json
    sleep 10
done
