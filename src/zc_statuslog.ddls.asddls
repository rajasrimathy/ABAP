@EndUserText.label: 'Status Log'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
define view entity ZC_STATUSLOG as projection on ZR_STATUSLOG
{
    key ZStatuslogUuid,
    ZPaymentUuid,
    ZResponsecode,
    ZResponse,
    ZCreatedby,
    ZCreatedate,
    ZLastchangedby,
    ZLastchangedate, 
    ZLocallastchangedate,
    /* Associations */
    _Details: redirected to parent ZC_PAYMENTDETAILS
}
