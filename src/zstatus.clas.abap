CLASS zstatus DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_apj_dt_exec_object .
    INTERFACES if_apj_rt_exec_object .
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zstatus IMPLEMENTATION.


  METHOD if_apj_dt_exec_object~get_parameters.
  ENDMETHOD.


  METHOD if_apj_rt_exec_object~execute.

    DATA lv_short_time_stamp TYPE timestampl.
    GET TIME STAMP FIELD lv_short_time_stamp.

    "Select all the payment details if payment sync is false.
    DATA: totalpaymentdetails TYPE TABLE OF zpaymentdetails,
          totals              TYPE zpaymentdetails.

    SELECT ( '*' ) FROM zpaymentdetails WHERE z_statussync = '' AND z_paymentsync <> '' AND ( z_paymentstatuscode = '000' OR z_paymentstatuscode = '005' ) INTO TABLE @totalpaymentdetails.

    "Get one by one in loop
    LOOP AT totalpaymentdetails INTO totals.

      DATA: system_uuid_log TYPE REF TO if_system_uuid,
            uuid_log        TYPE sysuuid_c32.

      DATA: ls_statuslog TYPE zstatuslog.

      " Select particular details
      SELECT * FROM zpaymentdetails WHERE z_payment_uuid = @totals-z_payment_uuid INTO TABLE @DATA(paymentdetail).

      DATA instruments TYPE TABLE OF zinstrumentlist.

      LOOP AT paymentdetail INTO DATA(getdetails).


        "Payment and Status Sync Check
        DATA statussync.
        DATA paymentsync.
        DATA paymentstatus TYPE string.
        DATA paymentstatuscode TYPE string.

        paymentsync = getdetails-z_paymentsync.
        statussync = getdetails-z_statussync.
        paymentstatus = getdetails-z_paymentstatus.
        paymentstatuscode = getdetails-z_paymentstatuscode.


        IF statussync IS INITIAL AND paymentsync IS NOT INITIAL AND ( paymentstatuscode = '000' OR paymentstatuscode = '005' ).

          "Create client id and client secret field for pass value runtime via API.
          DATA clientid TYPE string.
          DATA clientsecret TYPE string.

          DATA: lt_data TYPE TABLE OF zconfiguration,
                ls_data TYPE zconfiguration.

          "Select data from a configuration table
          SELECT * FROM zconfiguration WHERE z_id = 'ROOT' INTO TABLE @lt_data.

          IF lt_data IS NOT INITIAL.
            LOOP AT lt_data INTO ls_data.
              clientid = ls_data-z_client_id.
              clientsecret = ls_data-z_client_secret.
            ENDLOOP.
          ENDIF.

          TRY.
              "API call for Post Payment Details.
              DATA(loo_destination_status) = cl_http_destination_provider=>create_by_comm_arrangement(
                                     comm_scenario  = 'ZSTATUSAPI_SC'
                                   ).
              DATA(loo_http_client_status) = cl_web_http_client_manager=>create_by_http_destination( loo_destination_status ).

              DATA(loo_request_status) = loo_http_client_status->get_http_request( ).

              loo_request_status->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/xml' ) ) ).

              DATA: lt_instrumentdata TYPE TABLE OF zinstrumentlist,
                    ls_instrumentdata TYPE zinstrumentlist.


              DATA bodycontent TYPE string.

              bodycontent = '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:rev="http://www.kotak.com/schemas/CMS_Generic/Reversal_Request.xsd">' &&
                        '<soap:Header/>' && '<soap:Body>' && '<rev:Reversal>' && '<rev:Header>' && '<rev:Req_Id>' && getdetails-z_paymentmessageid && '</rev:Req_Id>' &&
                        '<rev:Msg_Src>' && getdetails-z_messagesourcecode && '</rev:Msg_Src>' && '<rev:Client_Code>' && getdetails-z_clientcode && '</rev:Client_Code>' &&
                        '<rev:Date_Post>' && lv_short_time_stamp && '+5:30' && '</rev:Date_Post>' &&
                        '</rev:Header><rev:Details><!--Zero or more repetitions:-->' && '<rev:Msg_Id>' && getdetails-z_paymentmessageid &&
                        '</rev:Msg_Id>' && '</rev:Details>' && '</rev:Reversal></soap:Body></soap:Envelope>'.

              DATA(xs) = cl_abap_conv_codepage=>create_out( codepage = `UTF-8` )->convert( bodycontent ).

              "API call for Post for Encrypt Details.
              DATA(loo_destination_encrypt) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario  = 'ZENCRYPTION_SC'
                                   ).
              DATA(loo_http_client_encrypt) = cl_web_http_client_manager=>create_by_http_destination( loo_destination_encrypt ).

              DATA(loo_request_encrypt) = loo_http_client_encrypt->get_http_request( ).

              loo_request_encrypt->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/json' ) ) ).


              bodycontent = '{ "x_string" : "' && xs && '" }'.

              loo_request_encrypt->set_text( bodycontent ).

              DATA(lo_response_encrypt) = loo_http_client_encrypt->execute( if_web_http_client=>post ).

              "Result
              DATA(lv_json_encrypt) = lo_response_encrypt->get_text( ).

              "Get Status.
              DATA(statuscode_encrypt) = lo_response_encrypt->get_status( )-code.

              IF ( statuscode_encrypt = 200 ).
                "Extract Response Details.
                DATA:
                  BEGIN OF encryption_tags,
                    statuscode TYPE string,
                    body       TYPE string,
                  END OF encryption_tags.
                /ui2/cl_json=>deserialize( EXPORTING json = lv_json_encrypt CHANGING data = encryption_tags ) .
              ENDIF.

              loo_request_status->set_text( encryption_tags-body ).

              "API call for Get Refresh Token.
              DATA(lo_destination_getrefershtoken) = cl_http_destination_provider=>create_by_comm_arrangement(
                                     comm_scenario  = 'ZGETREFRESHTOKEN_SC'
                                   ).
              DATA(lo_http_client_getrefreshtoken) = cl_web_http_client_manager=>create_by_http_destination( lo_destination_getrefershtoken ).

              DATA(lo_request_getrefreshtoken) = lo_http_client_getrefreshtoken->get_http_request( ).

              lo_request_getrefreshtoken->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/x-www-form-urlencoded' ) ) ).

              lo_request_getrefreshtoken->set_form_fields( VALUE #(
              ( name = 'client_id' value = clientid )
              ( name = 'client_secret' value = clientsecret )
              ( name = 'grant_type' value = 'client_credentials' ) ) ).

              "Execute Call.
              DATA(lo_response_getrefreshtoken) = lo_http_client_getrefreshtoken->execute( if_web_http_client=>post ).

              "Result
              DATA(lv_json_getrefreshtoken) = lo_response_getrefreshtoken->get_text( ).

              "Get Status.
              DATA(statuscode_getrefreshtoken) = lo_response_getrefreshtoken->get_status( )-code.

              IF ( statuscode_getrefreshtoken = 200 ).
                "Extract Response Details.
                DATA:
                  BEGIN OF ts_tags,
                    access_token TYPE string,
                    token_type   TYPE string,
                    expires_in   TYPE string,
                    scope        TYPE string,
                  END OF ts_tags.
                /ui2/cl_json=>deserialize( EXPORTING json = lv_json_getrefreshtoken CHANGING data = ts_tags ) .

                "DATA(accToken) = 'Bearer' && '   ' && ts_tags-access_token.

                CONCATENATE 'Bearer' ts_tags-access_token INTO DATA(acctoken) SEPARATED BY space.

                loo_request_status->set_header_fields( VALUE #(
                ( name = 'Authorization' value = acctoken ) ) ).

                "Execute Call.
                DATA(loo_response_status) = loo_http_client_status->execute( if_web_http_client=>post ).

                "Result
                DATA(lv_json_status) = loo_response_status->get_text( ).

                "Get Status.
                DATA(statuscode_status) = loo_response_status->get_status( )-code.

                "API call for Post for Decrypt Details.
                DATA(loo_destination_decrypt) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario  = 'ZDECRYPTION_SC'
                                     ).
                DATA(loo_http_client_decrypt) = cl_web_http_client_manager=>create_by_http_destination( loo_destination_decrypt ).

                DATA(loo_request_decrypt) = loo_http_client_decrypt->get_http_request( ).

                loo_request_decrypt->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/json' ) ) ).

                DATA decryptcontent TYPE string.

                decryptcontent = '{ "EncryptedString" : "' && lv_json_status && '" }'.

                loo_request_decrypt->set_text( decryptcontent ).

                DATA(lo_response_decrypt) = loo_http_client_decrypt->execute( if_web_http_client=>post ).

                "Result
                DATA(lv_json_decrypt) = lo_response_decrypt->get_text( ).

                "Get Status.
                DATA(statuscode_decrypt) = lo_response_decrypt->get_status( )-code.


                IF ( statuscode_status = 200 ).

                  REPLACE ALL OCCURRENCES OF '\' IN lv_json_decrypt WITH ''.

                  DATA removelastlen TYPE i.
                  removelastlen = strlen( lv_json_decrypt ).
                  removelastlen = removelastlen - 1.
                  lv_json_decrypt = lv_json_decrypt+0(removelastlen).

                  DATA removefirstlen TYPE i.
                  removefirstlen = strlen( lv_json_decrypt ).
                  removefirstlen = removefirstlen - 1.
                  lv_json_decrypt = lv_json_decrypt+1(removefirstlen).

                  DATA(decryptedxml) = cl_abap_conv_codepage=>create_out( )->convert( source = lv_json_decrypt ).
                  DATA(ixml_pa) = cl_ixml_core=>create( ).
                  DATA(stream_factory_pa) = ixml_pa->create_stream_factory( ).
                  DATA(document_pa) = ixml_pa->create_document( ).

                  DATA(parser_pa) = ixml_pa->create_parser(
                                     istream = stream_factory_pa->create_istream_xstring( string = decryptedxml )
                                     document = document_pa
                                     stream_factory = stream_factory_pa ).
                  DATA(parsing_check) = parser_pa->parse( ).
                  IF parsing_check = 0.
                    DATA(envelope) = document_pa->get_root_element( ).
                    DATA(body) = envelope->get_last_child( ).
                    DATA(header) = body->get_last_child( ).
                    DATA(detailslist) = header->get_last_child(  ).
                    IF detailslist->get_name(  ) = 'Details'.
                      DATA(details) = detailslist->get_children( ).
                      DATA(detailslength) = details->get_length(  ).
                      DATA(i) = 0.
                      WHILE detailslength > i.
                        DATA msg_id TYPE string.
                        DATA status_code TYPE string.
                        DATA status_desc TYPE string.
                        DATA(detailschild) = details->get_item( i ).
                        DATA(detail) = detailschild->get_children(  ).
                        DATA(detaillength) = detail->get_length(  ).
                        DATA(j) = 0.
                        WHILE detaillength > j.
                          DATA(detailitemdata) = detail->get_item( j ).
                          IF detailitemdata->get_name( ) = 'InstRefNo'.
                            msg_id = detailitemdata->get_value( ).
                          ELSEIF
                            detailitemdata->get_name( ) = 'Status_Code'.
                            status_code = detailitemdata->get_value( ).
                          ELSEIF
                            detailitemdata->get_name( ) = 'Status_Desc'.
                            status_desc = detailitemdata->get_value( ).
                          ENDIF.
                          j = j + 1.
                        ENDWHILE.

                        SELECT * FROM zinstrumentlist WHERE z_messageid = @msg_id and z_payment_uuid = @getdetails-z_payment_uuid INTO @DATA(instrument).
                          IF instrument IS NOT INITIAL.
                            UPDATE zinstrumentlist SET z_statuscode = @status_code ,z_statusremark = @status_desc WHERE z_messageid = @msg_id.
                            instrument-z_statuscode = status_code.
                            instrument-z_statusremark = status_desc.
                            APPEND instrument TO instruments.
                          ENDIF.
                        ENDSELECT.

                        i = i + 1.
                      ENDWHILE.
                      UPDATE zpaymentdetails SET z_statussync = 'X' WHERE z_payment_uuid = @getdetails-z_payment_uuid.
                    ENDIF.
                  ENDIF.

                  DATA totalinstrumentlistdetails TYPE TABLE OF zinstrumentlist.
                  DATA totalinstrument TYPE i.

                  "Total Instrument list details.
                  SELECT * FROM zinstrumentlist WHERE  z_payment_uuid = @getdetails-z_payment_uuid INTO TABLE @totalinstrumentlistdetails.
                  IF totalinstrumentlistdetails IS NOT INITIAL.
                    totalinstrument = lines( totalinstrumentlistdetails ).
                  ENDIF.

                  IF instruments IS NOT INITIAL .

                    DATA currentinstrument TYPE i.

                    DATA(processedlist) = instruments.
                    DATA(inprocesslist_c) = instruments.
                    DATA(inprocesslist_pa) = instruments.
                    DATA(inprocesslist_ps) = instruments.
                    DATA(inprocesslist_0) = instruments.
                    DATA(inprocesslist_empty) = instruments.

                    DELETE inprocesslist_c WHERE z_payment_uuid EQ getdetails-z_payment_uuid AND z_statuscode NE 'C'.

                    IF inprocesslist_c IS NOT INITIAL.
                      currentinstrument = lines( inprocesslist_c ).
                      IF currentinstrument IS NOT INITIAL.
                        UPDATE zpaymentdetails SET z_bankprocessedstatus = 'Few Instruments are In-process.' WHERE z_payment_uuid = @getdetails-z_payment_uuid.
                      ENDIF.
                    ELSE.
                      DELETE inprocesslist_pa WHERE z_payment_uuid EQ getdetails-z_payment_uuid AND z_statuscode NE 'PA'.

                      IF inprocesslist_pa IS NOT INITIAL.
                        currentinstrument = lines( inprocesslist_pa ).
                        IF currentinstrument IS NOT INITIAL.
                          UPDATE zpaymentdetails SET z_bankprocessedstatus = 'Few Instruments are In-process.' WHERE z_payment_uuid = @getdetails-z_payment_uuid.
                        ENDIF.
                      ELSE.
                        DELETE inprocesslist_ps WHERE z_payment_uuid EQ getdetails-z_payment_uuid AND z_statuscode NE 'PS'.

                        IF inprocesslist_ps IS NOT INITIAL.
                          currentinstrument = lines( inprocesslist_ps ).
                          IF currentinstrument IS NOT INITIAL.
                            UPDATE zpaymentdetails SET z_bankprocessedstatus = 'Few Instruments are In-process.' WHERE z_payment_uuid = @getdetails-z_payment_uuid.
                          ENDIF.
                        ELSE.
                          DELETE inprocesslist_0 WHERE z_payment_uuid EQ getdetails-z_payment_uuid AND z_statuscode NE 'O'.

                          IF inprocesslist_0 IS NOT INITIAL.
                            currentinstrument = lines( inprocesslist_0 ).
                            IF currentinstrument IS NOT INITIAL.
                              UPDATE zpaymentdetails SET z_bankprocessedstatus = 'Few Instruments are In-process.' WHERE z_payment_uuid = @getdetails-z_payment_uuid.
                            ENDIF.
                          ELSE.
                            DELETE processedlist WHERE z_payment_uuid EQ getdetails-z_payment_uuid AND z_statuscode NE 'U'.

                            IF processedlist IS NOT INITIAL.
                              currentinstrument = lines( processedlist ).
                              IF currentinstrument IS NOT INITIAL.
                                IF ( totalinstrument = currentinstrument ).
                                  UPDATE zpaymentdetails SET z_bankprocessedstatus = 'All Instruments are Processed.' WHERE z_payment_uuid = @getdetails-z_payment_uuid.
                                ELSE.
                                  UPDATE zpaymentdetails SET z_bankprocessedstatus = 'Few Instruments are Processed.' WHERE z_payment_uuid = @getdetails-z_payment_uuid.
                                ENDIF.
                              ENDIF.
                            ELSE.
                              UPDATE zpaymentdetails SET z_bankprocessedstatus = 'All Instruments are Failed.' WHERE z_payment_uuid = @getdetails-z_payment_uuid.
                            ENDIF.
                          ENDIF.
                        ENDIF.
                      ENDIF.
                    ENDIF.
                  ELSE.
                    UPDATE zpaymentdetails SET z_statussync = '' WHERE z_payment_uuid = @getdetails-z_payment_uuid.
                  ENDIF.

                  system_uuid_log = cl_uuid_factory=>create_system_uuid( ).
                  TRY.
                      uuid_log = system_uuid_log->create_uuid_c32( ).
                    CATCH cx_uuid_error.
                  ENDTRY.

                  ls_statuslog-z_statuslog_uuid  = uuid_log.
                  ls_statuslog-z_payment_uuid = getdetails-z_payment_uuid.
                  ls_statuslog-z_responsecode = statuscode_status.
                  ls_statuslog-z_response = lv_json_decrypt.
                  ls_statuslog-z_createdby = cl_abap_context_info=>get_user_technical_name( ).
                  ls_statuslog-z_createdate = lv_short_time_stamp.
                  ls_statuslog-z_lastchangedby = cl_abap_context_info=>get_user_technical_name( ).
                  ls_statuslog-z_lastchangedate = lv_short_time_stamp.
                  ls_statuslog-z_locallastchangedate = lv_short_time_stamp.

                  INSERT INTO zstatuslog VALUES @ls_statuslog.

                ELSE.
                  system_uuid_log = cl_uuid_factory=>create_system_uuid( ).
                  TRY.
                      uuid_log = system_uuid_log->create_uuid_c32( ).
                    CATCH cx_uuid_error.
                  ENDTRY.

                  ls_statuslog-z_statuslog_uuid  = uuid_log.
                  ls_statuslog-z_payment_uuid = getdetails-z_payment_uuid.
                  ls_statuslog-z_responsecode = statuscode_status.
                  ls_statuslog-z_response = lv_json_status.
                  ls_statuslog-z_createdby = cl_abap_context_info=>get_user_technical_name( ).
                  ls_statuslog-z_createdate = lv_short_time_stamp.
                  ls_statuslog-z_lastchangedby = cl_abap_context_info=>get_user_technical_name( ).
                  ls_statuslog-z_lastchangedate = lv_short_time_stamp.
                  ls_statuslog-z_locallastchangedate = lv_short_time_stamp.

                  INSERT INTO zstatuslog VALUES @ls_statuslog.
                ENDIF.

              ELSE.
                system_uuid_log = cl_uuid_factory=>create_system_uuid( ).
                TRY.
                    uuid_log = system_uuid_log->create_uuid_c32( ).
                  CATCH cx_uuid_error.
                ENDTRY.

                ls_statuslog-z_statuslog_uuid  = uuid_log.
                ls_statuslog-z_payment_uuid = getdetails-z_payment_uuid.
                ls_statuslog-z_responsecode = statuscode_getrefreshtoken.
                ls_statuslog-z_response = lv_json_getrefreshtoken.
                ls_statuslog-z_createdby = cl_abap_context_info=>get_user_technical_name( ).
                ls_statuslog-z_createdate = lv_short_time_stamp.
                ls_statuslog-z_lastchangedby = cl_abap_context_info=>get_user_technical_name( ).
                ls_statuslog-z_lastchangedate = lv_short_time_stamp.
                ls_statuslog-z_locallastchangedate = lv_short_time_stamp.

                INSERT INTO zstatuslog VALUES @ls_statuslog.
              ENDIF.

            CATCH cx_http_dest_provider_error.
              " handle exception here.

            CATCH cx_web_http_client_error.
              " handle exception here
          ENDTRY.
        ELSE.
          UPDATE zpaymentdetails SET z_statussync = 'X', z_bankprocessedstatus = 'All Instruments are Failed.' WHERE z_payment_uuid = @getdetails-z_payment_uuid.
        ENDIF.

      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
