@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Instrument List'
define view entity ZR_INSTRUMENTLIST
  as select from zinstrumentlist
  association to parent ZR_PAYMENTDETAILS as _Details on $projection.ZPaymentUuid = _Details.ZPaymentUuid
{
  key z_instrument_uuid     as ZInstrumentUuid,
      z_payment_uuid        as ZPaymentUuid,
      z_messageid           as ZMessageid,
      z_statuscode          as ZStatuscode,
      z_statusremark        as ZStatusremark,
      @Semantics.user.createdBy: true
      z_createdby           as ZCreatedby,
      @Semantics.systemDateTime.createdAt: true
      z_createdate          as ZCreatedate,
      @Semantics.user.localInstanceLastChangedBy: true
      z_lastchangedby       as ZLastchangedby,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      z_lastchangedate      as ZLastchangedate,
      @Semantics.systemDateTime.lastChangedAt: true
      z_locallastchangedate as ZLocallastchangedate,
      _Details // Make association public
}
