@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Payment Details'
define root view entity ZR_PAYMENTDETAILS
  as select from zpaymentdetails
  composition [0..*] of ZR_PAYMENTLOG     as _Log
  composition [0..*] of ZR_STATUSLOG      as _StatusLog
  composition [0..*] of ZR_INSTRUMENTLIST as _InstrumentLog
{
  key z_payment_uuid         as ZPaymentUuid,
      z_paymentstatus        as ZPaymentstatus,
      z_paymentstatuscode    as ZPaymentstatuscode,
      z_bankprocessedstatus  as ZBankProcessedStatus,
      z_paymentfilereference as ZPaymentFileReference,
      z_filecontent          as ZFileContent,
      z_encryptedfile        as ZEncryptedfile,
      z_paymentmessageid     as ZPaymentmessageid,
      z_paymentsync          as ZPaymentsync,
      z_statussync           as ZStatussync,
      z_clientcode           as ZClientcode,
      z_messagesourcecode    as ZMessagesourcecode,
      @Semantics.user.createdBy: true
      z_createdby            as ZCreatedby,
      @Semantics.systemDateTime.createdAt: true
      z_createdate           as ZCreatedate,
      @Semantics.user.localInstanceLastChangedBy: true
      z_lastchangedby        as ZLastchangedby,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      z_lastchangedate       as ZLastchangedate,
      @Semantics.systemDateTime.lastChangedAt: true
      z_locallastchangedate  as ZLocallastchangedate,
      _Log, // Make association public
      _StatusLog,
      _InstrumentLog
}
