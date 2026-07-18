## Runtime UI

### Form validation JavaScript

Status:
Not blocking.

Current output

alert('Error in form validation. ID=\''.input_.username.'\'.');

Expected

alert("Error in form validation. ID='input_username'.");

Reason

Legacy PHP string interpolation inside generated JavaScript.

Priority

Medium.

## NB-001 — Generated form validation JavaScript

**Status:** Open  
**Priority:** Medium  
**Area:** Runtime UI  
**File:** `framework/app/core_modules/htmlelements/classes/form_class_inc.php`

The generated validation alert currently contains JavaScript concatenation syntax rather than a literal element ID.

Current generated output:

```javascript
alert('Error in form validation. ID=\''.input_.username.'\'.');
```

Expected output:

```javascript
alert("Error in form validation. ID='input_username'.");
```

This does not currently block form submission, but it must be corrected during the PHP 8.2 runtime cleanup.

## UTF8 conversion

## Chisimba remote module server
Medium term:
Make the repository URL an optional system configuration value.
If blank, operate entirely offline.
Long term:
Stand up a new Chisimba Revival package repository (perhaps backed by GitHub releases or a simple JSON API) that modern installations can query.

## Discussion forum replies do not show up.

I agree about the missing replies: since the module loads and the forum interaction works without a PHP fatal, that now looks more like a data retrieval, permissions, threading, or display-flow issue than a PHP 8 compatibility blocker. We should record it for later functional testing rather than derail the compatibility work now.

My guess

Given the work we've done over the last few days, my leading candidates are:

The reply action is not reaching the save code
incorrect controller dispatch
wrong event name
form action mismatch
The save code exits early
permission check
validation
transaction rollback
silent redirect
A PHP 8 compatibility issue inside the reply path
something now evaluates differently
but no fatal occurs because the code simply returns
I would not investigate this today

This is no longer a framework compatibility issue.
