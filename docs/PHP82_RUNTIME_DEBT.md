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
