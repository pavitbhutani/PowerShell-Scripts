#!/bin/bash
# This script will check to see if a website is up ONLY by pinging the urls.
# If one or more urls are down, an email wil be sent uing mail command.
# Script only checks urls once, create scheduled task using crontab.

echo "Checking URLs."
urls=('www.google.com' 'www.facebook.com' 'www.apple.com')

# Define function to send email.
send()	{
				toemail="your_email_here"
				body=("$@")
				printf "%s\n" "${body[@]}"|mail -s "${#body[@]} URL(s) DOWN" "$toemail"
}

# Check if URL is reachable or not through ping.
# If URL is down, add it to urlsDown variable.
urlsDown=()
for url in "${urls[@]}"
do
	echo ""
	echo "Checking url $url."
	ping -q -c5 $url > /dev/null

	if [ $? -eq 0 ]; then
		echo "Url $url is UP."
	else
	  	echo "Url $url is DOWN."
			urlsDown[${#urlsDown[@]}]="$url DOWN at `date`."
	fi
done
echo ""

# Check if urlsDown variable is null or not and send email.
if [ ${#urlsDown[@]} -eq 0 ]; then
	echo "No URL down."
else
	echo "${#urlsDown[@]} URL(s) down, sending email."
	send "${urlsDown[@]}"
fi

#exit
