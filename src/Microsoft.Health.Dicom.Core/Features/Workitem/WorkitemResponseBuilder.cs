﻿// -------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
// -------------------------------------------------------------------------------------------------

using System;
using FellowOakDicom;
using EnsureThat;
using Microsoft.Health.Dicom.Core.Features.Routing;
using Microsoft.Health.Dicom.Core.Messages.WorkitemMessages;

namespace Microsoft.Health.Dicom.Core.Features.Workitem
{
    /// <summary>
    /// Provides functionality to build the response for the workitem transactions.
    /// </summary>
    public class WorkitemResponseBuilder : IWorkitemResponseBuilder
    {
        private readonly IUrlResolver _urlResolver;

        private DicomDataset _dataset;

        public WorkitemResponseBuilder(IUrlResolver urlResolver)
        {
            EnsureArg.IsNotNull(urlResolver, nameof(urlResolver));

            _urlResolver = urlResolver;
        }

        /// <inheritdoc />
        public AddWorkitemResponse BuildAddResponse()
        {
            Uri url = null;
            WorkitemResponseStatus status = WorkitemResponseStatus.Failure;

            if (_dataset.TryGetSingleValue<string>(DicomTag.RequestedSOPInstanceUID, out var workitemInstanceUid)
                && !_dataset.TryGetSingleValue<ushort>(DicomTag.FailureReason, out var _))
            {
                // There are only success.
                status = WorkitemResponseStatus.Success;
                url = _urlResolver.ResolveRetrieveWorkitemUri(workitemInstanceUid);
            }

            return new AddWorkitemResponse(status, url);
        }

        /// <inheritdoc />
        public CancelWorkitemResponse BuildCancelResponse()
        {
            var status = WorkitemResponseStatus.Failure;

            if (!_dataset.TryGetSingleValue<ushort>(DicomTag.FailureReason, out var _))
            {
                // There are only success.
                status = WorkitemResponseStatus.Success;
            }

            return new CancelWorkitemResponse(status);
        }

        /// <inheritdoc />
        public void AddSuccess(DicomDataset dicomDataset)
        {
            EnsureArg.IsNotNull(dicomDataset, nameof(dicomDataset));

            _dataset = dicomDataset;
        }

        /// <inheritdoc />
        public void AddFailure(DicomDataset dicomDataset, ushort failureReasonCode)
        {
            _dataset = dicomDataset ?? new DicomDataset();

            _dataset.Add(DicomTag.FailureReason, failureReasonCode);
        }
    }
}