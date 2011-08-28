UPDATE "Workspace"
   SET email_notification_from_address = 'noreply@socialtext.com'
 WHERE email_notification_from_address = '';
