# Coding challenge

To solve this challenge I decided not to connect to the instances at all. The instances are sealed and they do not need public SSH access. This is actually best practice but of course it would have been much easier to just SSH into the instances using a Terraform provisioner.

Instead I decided to do it using a clever solution: The instances contain a user-data script that will have them ping each other when they boot and send a message to an SQS queue. Terraform reads from this queue and stores it in an output, using my helper script `messages.sh`.

The rest I believe is pretty straightforward.
