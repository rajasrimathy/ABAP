@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Status Log'
define view entity ZR_STATUSLOG
  as select from zstatuslog
  association to parent ZR_PAYMENTDETAILS as _Details on $projection.ZPaymentUuid = _Details.ZPaymentUuid
{
  key z_statuslog_uuid      as ZStatuslogUuid,
      z_payment_uuid        as ZPaymentUuid,
      z_responsecode        as ZResponsecode,
      z_response            as ZResponse,
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
