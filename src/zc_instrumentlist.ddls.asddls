@EndUserText.label: 'Instrument List'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
define view entity ZC_INSTRUMENTLIST as projection on ZR_INSTRUMENTLIST
{
    key ZInstrumentUuid,
    ZPaymentUuid,
    ZMessageid,
    ZStatuscode,
    ZStatusremark,
    ZCreatedby,
    ZCreatedate,
    ZLastchangedby,
    ZLastchangedate,
    ZLocallastchangedate,
    /* Associations */
     _Details: redirected to parent ZC_PAYMENTDETAILS
}
