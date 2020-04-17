# mediagoblin_to_static
Converts MediaGoblin site to static HTML (trying to preserve most of directory structure)

Might be useful, for example, when your MediaGoblin instance breaks when upgrading to Debian Buster...

* make sure you edit `mg_to_static.pl` first and set correct directories to which this user have permission to write.

* Scripts needs to access your Postgres database, so it probably should be run as:

```
sudo -u postgres ./mg_to_static.pl
```

* Modify your apache so it can access this data:

```
<VirtualHost *:80>
        ServerName mediagoblin.example.com
        
        DocumentRoot /var/www/html/mg_html
        <Directory "/var/www/html/mg_html">
                Require all granted
                #Options Indexes
        </Directory>

        Alias /media_entries /var/lib/mediagoblin/default/media/public/media_entries
        <Directory "/var/lib/mediagoblin/default/media/public/media_entries">
                Require all granted
                #Options Indexes
        </Directory>

        CustomLog /var/log/apache2/mediagoblin.access.log combined
        ErrorLog /var/log/apache2/mediagoblin_error.log
</VirtualHost>
```
