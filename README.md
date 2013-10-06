owncloud2sylpheed
=================

My first own ruby/git project. Extracts email contacts from an owncloud server and creates an addressbook file for use with the e-mail program "sylpheed".

At first start it will ask for the server, path, username and password and store it to "~/.config/owncloud2sylpheed". Later runs read the settings from this file.

The script will fetch all contacts from the owncloud server and create an XML structure that is usable with sylpheed. If there is already an addressbook with name "owncloud", the corresponding file will be overwritten. Otherwise a new addressbook of that name is created.

Usage:

```Shell
ruby owncloud2sylpheed.rb
```